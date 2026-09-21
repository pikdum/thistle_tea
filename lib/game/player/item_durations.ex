defmodule ThistleTea.Game.Player.ItemDurations do
  @moduledoc """
  Owns one timer for the player's earliest item deadline, including banked
  items. Inventory publication registers new deadlines and projects countdowns.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemLifetime
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message.SmsgItemTimeUpdate
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore

  def restore(%Character{} = character, now \\ Time.now()) do
    {:ok, changes} = ItemLifetime.plan(character, now, :login, &ItemStore.get/1)
    commit(changes)
    %{character | player: changes.player, internal: %{character.internal | item_logout_at: nil}}
  end

  def start(%State{} = state), do: sync(%{state | item_durations_active?: true})

  def set_remaining(%State{character: %Character{} = character} = state, entry, seconds)
      when is_integer(seconds) and seconds in 1..604_800 do
    now = Time.now()

    items =
      character.player
      |> Inventory.all_owned_items(&ItemStore.get/1)
      |> Enum.filter(&(&1.item.owner == character.object.guid and &1.object.entry == entry and &1.item.duration > 0))

    batch =
      Enum.reduce(items, Batch.new(character.player), &Batch.update(&2, ItemLifetime.set_remaining(&1, seconds, now)))

    {InventoryUpdate.apply(state, Inventory.plan(batch, &ItemStore.get/1)), length(items)}
  end

  def sync(state, now \\ Time.now())

  def sync(%State{item_durations_active?: true, character: %Character{} = character} = state, now) do
    items =
      character.player
      |> Inventory.all_owned_items(&ItemStore.get/1)
      |> Enum.filter(&(&1.item.owner == character.object.guid))
      |> Enum.map(fn item ->
        updated = ItemLifetime.start(item, now)
        if updated != item, do: ItemStore.put(updated)
        send_time(updated, now)
        updated
      end)

    deadline = items |> Enum.map(&ItemLifetime.deadline/1) |> Enum.reject(&is_nil/1) |> Enum.min(fn -> nil end)
    schedule(state, deadline, now)
  end

  def sync(state, _now), do: state

  def tick(state, token, now \\ Time.now())

  def tick(%State{item_duration_timer: %{token: token}} = state, token, now) do
    state |> cancel_timer() |> expire_due(now) |> sync(now)
  end

  def tick(state, _token, _now), do: state

  def expire_due(state, now \\ Time.now())

  def expire_due(%State{character: %Character{} = character} = state, now) do
    {:ok, changes} = ItemLifetime.plan(character, now, :online, &ItemStore.get/1)

    if changes.changed == %{} and changes.destroyed == %{} do
      state
    else
      state
      |> cancel_expired_cast(changes)
      |> InventoryUpdate.apply({:ok, changes})
      |> Looting.close_unavailable()
    end
  end

  def expire_due(state, _now), do: state

  def logout(state, now \\ Time.now())

  def logout(%State{character: %Character{} = character} = state, now) do
    state = cancel_timer(%{state | item_durations_active?: false})
    {:ok, changes} = ItemLifetime.plan(character, now, :logout, &ItemStore.get/1)

    state =
      if changes.changed == %{} and changes.destroyed == %{},
        do: state,
        else: state |> cancel_expired_cast(changes) |> InventoryUpdate.apply({:ok, changes})

    %{state | character: %{state.character | internal: %{state.character.internal | item_logout_at: now}}}
  end

  def logout(%State{} = state, _now), do: cancel_timer(%{state | item_durations_active?: false})

  defp cancel_expired_cast(%State{character: %{internal: %{casting: %Cast{cast_item_guid: guid}}}} = state, changes) do
    if Map.has_key?(changes.destroyed, guid), do: Spellcasting.cancel(state), else: state
  end

  defp cancel_expired_cast(state, _changes), do: state

  defp send_time(item, now) do
    if ItemLifetime.deadline(item) do
      projected = ItemLifetime.project(item, now)
      Network.send_packet(%SmsgItemTimeUpdate{guid: item.object.guid, duration: projected.item.duration})
    end
  end

  defp schedule(%State{item_duration_timer: %{deadline: deadline}} = state, deadline, _now), do: state

  defp schedule(state, nil, _now), do: cancel_timer(state)

  defp schedule(state, deadline, now) do
    state = cancel_timer(state)
    token = make_ref()
    ref = Process.send_after(self(), {:item_duration_tick, token}, min(max(deadline - now, 1), 86_400_000))
    %{state | item_duration_timer: %{token: token, ref: ref, deadline: deadline}}
  end

  defp cancel_timer(%State{item_duration_timer: %{ref: ref}} = state) do
    Process.cancel_timer(ref)
    %{state | item_duration_timer: nil}
  end

  defp cancel_timer(state), do: state

  defp commit(changes) do
    Enum.each(ChangeSet.destroyed_items(changes), &ItemStore.delete(&1.object.guid))
    Enum.each(ChangeSet.changed_items(changes), &ItemStore.put/1)
  end
end
