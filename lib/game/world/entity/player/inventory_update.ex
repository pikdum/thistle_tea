defmodule ThistleTea.Game.World.Entity.Player.InventoryUpdate do
  @moduledoc """
  Applies the result of a pure inventory operation to the player session:
  sends item create/values updates on success or the inventory-change-failure
  packet on error.

  All outbound packets for an inventory change are emitted here so their order
  stays fixed: quest objective progress first, then destroys, the create block
  for a newly placed item, item values, and the player's own values. The client
  renders the "Item: x/y" popup as its current count plus the packet's count,
  so a create block ahead of the progress packet shows one too many.
  """
  import Kernel, except: [apply: 2, apply: 3]

  alias ThistleTea.Game.Core.Combat.AttackTimers
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Core.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Core.Item.EquipmentTransitions
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgInventoryChangeFailure
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.Player.ConditionContext
  alias ThistleTea.Game.World.Entity.Player.Equipment
  alias ThistleTea.Game.World.Entity.Player.ItemDurations
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Presence

  def apply(state, result, placement \\ nil)

  def apply(%Character{} = character, {:ok, %ChangeSet{} = change_set}, _placement) do
    commit_items(change_set)
    %{character | player: change_set.player}
  end

  def apply(state, {:ok, %Player{} = player}, placement) do
    apply(state, {:ok, %{player: player, items: [], destroyed: []}}, placement)
  end

  def apply(state, {:ok, %ChangeSet{} = change_set}, _placement) do
    old_counts = Quests.quest_item_counts(state.character)
    commit_items(change_set)

    apply_committed(state, change_set, old_counts)
  end

  def apply(state, {:ok, %{player: %Player{} = player, items: items} = result}, placement) do
    old_counts = Quests.quest_item_counts(state.character)
    destroyed = Map.get(result, :destroyed, [])

    Enum.each(destroyed, fn item -> ItemStore.delete(item.object.guid) end)
    Enum.each(items, fn item -> ItemStore.put(item) end)

    character = sync_character(state.character, player)

    state =
      state
      |> Map.put(:character, character)
      |> Quests.on_inventory_changed(old_counts)

    Enum.each(destroyed, fn item ->
      Outbound.send_packet(%Message.SmsgDestroyObject{guid: item.object.guid})
    end)

    send_created(placement)

    Enum.each(items, fn item ->
      item
      |> UpdateObject.item_values_update()
      |> Outbound.send_packet()
    end)

    finish_update(state)
  end

  def apply(state, {:error, error, item1_guid, item2_guid}, _placement) do
    send_failure(error, item1_guid, item2_guid)
    state
  end

  defp commit_items(%ChangeSet{} = change_set) do
    Enum.each(ChangeSet.destroyed_items(change_set), fn item -> ItemStore.delete(item.object.guid) end)
    Enum.each(ChangeSet.changed_items(change_set) ++ ChangeSet.placed_items(change_set), &ItemStore.put/1)
  end

  def apply_committed(state, %ChangeSet{} = change_set, old_counts, outgoing \\ []) do
    destroyed = ChangeSet.destroyed_items(change_set)
    changed = ChangeSet.changed_items(change_set)

    character = sync_character(state.character, change_set.player)

    state =
      state
      |> Map.put(:character, character)
      |> Quests.on_inventory_changed(old_counts)

    Enum.each(Enum.uniq(outgoing ++ Enum.map(destroyed, & &1.object.guid)), fn guid ->
      Outbound.send_packet(%Message.SmsgDestroyObject{guid: guid})
    end)

    Enum.each(change_set.placements, fn
      %Placement{status: :placed, item: %Item{} = item} ->
        Outbound.send_packet(UpdateObject.from_item(item))

      %Placement{} ->
        :ok
    end)

    Enum.each(changed, fn item ->
      item
      |> UpdateObject.item_values_update()
      |> Outbound.send_packet()
    end)

    finish_update(state)
  end

  def sync_character(%Character{} = character, %Player{} = player) do
    now = Time.now()

    %{character | player: player}
    |> Equipment.sync_stats()
    |> EquipmentTransitions.apply(character.player, &ItemStore.get/1, &SpellLoader.cached/1, now)
    |> AttackTimers.equipment_changed(character, now)
  end

  defp finish_update(state) do
    state = sync_condition_subject(state)
    broadcast_player(state)
    character = state.character |> EventSink.emit_pending(Context.new(self())) |> store_character()
    ItemDurations.sync(%{state | character: character})
  end

  def commit_placement(%Item{} = item, placement) do
    case placement do
      {:placed, {bag, slot}, placed} ->
        ItemStore.put(placed)
        {bag, slot}

      :merged ->
        ItemStore.delete(item.object.guid)
        {Inventory.bag_0(), 0xFFFFFFFF}
    end
  end

  defp send_created({:placed, _pos, placed}) do
    Outbound.send_packet(UpdateObject.from_item(placed))
  end

  defp send_created(_placement), do: :ok

  defp broadcast_player(state) do
    %UpdateObject{
      update_type: :values,
      object_type: :player
    }
    |> struct(Map.from_struct(state.character))
    |> World.broadcast_packet(state.character)
  end

  defp sync_condition_subject(%{character: %Character{} = character} = state) do
    Presence.sync(character, %{condition_subject: ConditionContext.snapshot(character).target})
    state
  end

  def send_failure(error, item1_guid, item2_guid) do
    Outbound.send_packet(%SmsgInventoryChangeFailure{
      code: Inventory.error_code(error),
      required_level: required_level(error, item1_guid),
      item1_guid: item1_guid,
      item2_guid: item2_guid
    })
  end

  defp required_level(:cant_equip_level_i, item_guid) do
    case ItemStore.get(item_guid) do
      %Item{} = item -> Item.template(item).required_level
      _ -> 0
    end
  end

  defp required_level(_error, _item_guid), do: 0

  defp store_character(%Character{id: id} = character) when is_integer(id) and id > 0 do
    CharacterStore.put(character)
  end

  defp store_character(%Character{} = character), do: character
end
