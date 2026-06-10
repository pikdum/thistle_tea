defmodule ThistleTea.Game.Network.InventoryUpdate do
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message.SmsgInventoryChangeFailure
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore

  def apply(state, {:ok, %Player{} = player}) do
    character =
      %{state.character | player: player}
      |> ThistleTea.Character.sync_mainhand_stats()

    %UpdateObject{
      update_type: :values,
      object_type: :player
    }
    |> struct(Map.from_struct(character))
    |> World.broadcast_packet(character)

    Map.put(state, :character, character)
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
