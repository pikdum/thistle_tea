defmodule ThistleTea.Game.Entity.Logic.ItemLifetime do
  @moduledoc """
  Pure timed-item deadlines, offline conjured-item cleanup, and inventory
  removal plans. Deadlines survive transfers without refreshing an item's life.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemDuration
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet

  @conjured_offline_ms 15 * 60_000

  def set_remaining(%Item{} = item, seconds, now) when is_integer(seconds) and seconds > 0 do
    item
    |> put_duration(%ItemDuration{remaining_ms: seconds * 1_000, expires_at: now + seconds * 1_000})
    |> project(now)
  end

  def start(%Item{} = item, now) do
    case duration(item) do
      %ItemDuration{expires_at: nil, remaining_ms: remaining} = duration ->
        put_duration(item, %{duration | expires_at: now + remaining})

      %ItemDuration{} ->
        item

      nil ->
        if (item.item.duration || 0) > 0,
          do:
            put_duration(item, %ItemDuration{
              remaining_ms: item.item.duration * 1_000,
              expires_at: now + item.item.duration * 1_000
            }),
          else: item
    end
  end

  def remaining_ms(%Item{} = item, now) do
    case duration(item) do
      %ItemDuration{expires_at: expires_at} when is_integer(expires_at) -> max(expires_at - now, 0)
      %ItemDuration{remaining_ms: remaining} -> remaining
      nil -> max(item.item.duration || 0, 0) * 1_000
    end
  end

  def deadline(%Item{} = item) do
    case duration(item) do
      %ItemDuration{expires_at: expires_at} -> expires_at
      nil -> nil
    end
  end

  def expired?(%Item{} = item, now), do: not is_nil(duration(item)) and remaining_ms(item, now) == 0

  def project(%Item{} = item, now) do
    %{item | item: %{item.item | duration: div(remaining_ms(item, now) + 999, 1_000)}}
  end

  def suspend(%Item{} = item, now) do
    if duration(item) && not realtime?(item) do
      item
      |> put_duration(%ItemDuration{remaining_ms: remaining_ms(item, now)})
      |> project(now)
    else
      item
    end
  end

  def plan(%Character{} = character, now, phase, get_item) when phase in [:online, :login, :logout] do
    items =
      character.player
      |> Inventory.all_owned_items(get_item)
      |> Enum.filter(&(&1.item.owner == character.object.guid))

    expired = Enum.filter(items, &remove?(&1, character, now, phase))
    removed = removal_guids(expired, items)

    batch =
      items
      |> Enum.reverse()
      |> Enum.reduce(Batch.new(character.player), fn item, batch ->
        if MapSet.member?(removed, item.object.guid),
          do: Batch.consume_item(batch, item.object.guid, item.item.stack_count),
          else: batch
      end)

    with {:ok, changes} <- Inventory.plan(batch, get_item) do
      surviving = Enum.reject(items, &MapSet.member?(removed, &1.object.guid))

      {:ok,
       Enum.reduce(surviving, changes, fn item, changes ->
         current = ChangeSet.get_item(changes, item.object.guid, get_item)
         update_duration(changes, current, now, phase)
       end)}
    end
  end

  defp update_duration(changes, item, now, phase) do
    updated = if phase == :logout, do: suspend(item, now), else: start(item, now)

    if updated == item,
      do: changes,
      else: ChangeSet.absorb(changes, %{player: changes.player, items: [updated], destroyed: []})
  end

  defp remove?(item, character, now, :login) do
    offline = character.internal.item_logout_at
    expired?(item, now) or (is_integer(offline) and now - offline > @conjured_offline_ms and conjured?(item))
  end

  defp remove?(item, _character, now, _phase), do: expired?(item, now)

  defp removal_guids(expired, items) do
    removed = MapSet.new(expired, & &1.object.guid)

    Enum.reduce(items, removed, fn item, removed ->
      if MapSet.member?(removed, item.item.contained), do: MapSet.put(removed, item.object.guid), else: removed
    end)
  end

  defp duration(%Item{internal: internal}), do: Map.get(internal, :duration)
  defp put_duration(item, duration), do: %{item | internal: Map.put(item.internal, :duration, duration)}
  defp realtime?(item), do: (Item.template(item).flags &&& 0x10000) != 0
  defp conjured?(item), do: (Item.template(item).flags &&& 2) != 0
end
