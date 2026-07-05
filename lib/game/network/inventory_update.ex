defmodule ThistleTea.Game.Network.InventoryUpdate do
  @moduledoc """
  Applies the result of a pure inventory operation to the player session:
  sends item create/values updates on success or the inventory-change-failure
  packet on error.
  """
  import Kernel, except: [apply: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgInventoryChangeFailure
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore

  def apply(state, {:ok, %Player{} = player}) do
    apply(state, {:ok, %{player: player, items: [], destroyed: []}})
  end

  def apply(state, {:ok, %{player: %Player{} = player, items: items} = result}) do
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

    Enum.each(items, fn item ->
      item
      |> UpdateObject.item_values_update()
      |> Network.send_packet()
    end)

    %UpdateObject{
      update_type: :values,
      object_type: :player
    }
    |> struct(Map.from_struct(state.character))
    |> World.broadcast_packet(state.character)

    state
  end

  def apply(state, {:error, error, item1_guid, item2_guid}) do
    send_failure(error, item1_guid, item2_guid)
    state
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
