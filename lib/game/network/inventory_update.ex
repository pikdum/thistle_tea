defmodule ThistleTea.Game.Network.InventoryUpdate do
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

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgInventoryChangeFailure
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore

  def apply(state, result, placement \\ nil)

  def apply(state, {:ok, %Player{} = player}, placement) do
    apply(state, {:ok, %{player: player, items: [], destroyed: []}}, placement)
  end

  def apply(state, {:ok, %ChangeSet{} = change_set}, _placement) do
    old_counts = Quests.quest_item_counts(state.character)
    destroyed = ChangeSet.destroyed_items(change_set)
    changed = ChangeSet.changed_items(change_set)
    placed = ChangeSet.placed_items(change_set)

    Enum.each(destroyed, fn item -> ItemStore.delete(item.object.guid) end)
    Enum.each(changed ++ placed, &ItemStore.put/1)

    character =
      %{state.character | player: change_set.player}
      |> Character.sync_equipment_stats()

    state =
      state
      |> Map.put(:character, character)
      |> Quests.on_inventory_changed(old_counts)

    Enum.each(destroyed, fn item ->
      Network.send_packet(%Message.SmsgDestroyObject{guid: item.object.guid})
    end)

    Enum.each(change_set.placements, fn
      %Placement{status: :placed, item: %Item{} = item} ->
        Network.send_packet(UpdateObject.from_item(item))

      %Placement{} ->
        :ok
    end)

    Enum.each(changed, fn item ->
      item
      |> UpdateObject.item_values_update()
      |> Network.send_packet()
    end)

    broadcast_player(state)
    state
  end

  def apply(state, {:ok, %{player: %Player{} = player, items: items} = result}, placement) do
    old_counts = Quests.quest_item_counts(state.character)
    destroyed = Map.get(result, :destroyed, [])

    Enum.each(destroyed, fn item -> ItemStore.delete(item.object.guid) end)
    Enum.each(items, fn item -> ItemStore.put(item) end)

    character =
      %{state.character | player: player}
      |> Character.sync_equipment_stats()

    state =
      state
      |> Map.put(:character, character)
      |> Quests.on_inventory_changed(old_counts)

    Enum.each(destroyed, fn item ->
      Network.send_packet(%Message.SmsgDestroyObject{guid: item.object.guid})
    end)

    send_created(placement)

    Enum.each(items, fn item ->
      item
      |> UpdateObject.item_values_update()
      |> Network.send_packet()
    end)

    broadcast_player(state)

    state
  end

  def apply(state, {:error, error, item1_guid, item2_guid}, _placement) do
    send_failure(error, item1_guid, item2_guid)
    state
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
    Network.send_packet(UpdateObject.from_item(placed))
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

  def send_failure(error, item1_guid, item2_guid) do
    Network.send_packet(%SmsgInventoryChangeFailure{
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
end
