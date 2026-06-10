defmodule ThistleTea.Game.Network.Message.SmsgLootResponse do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOOT_RESPONSE

  alias ThistleTea.Game.Entity.Logic.Loot

  @loot_type_corpse 1

  defstruct [:guid, :loot, loot_type: @loot_type_corpse]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, loot_type: loot_type, loot: %Loot{} = loot}) do
    items = Enum.reject(loot.items, & &1.looted)

    items_binary =
      items
      |> Enum.map_join(fn item ->
        <<item.slot, item.item_id::little-size(32), item.count::little-size(32), item.display_id::little-size(32),
          0::little-size(32), 0::little-size(32), 0>>
      end)

    <<guid::little-size(64), loot_type, loot.gold::little-size(32), Enum.count(items)>> <> items_binary
  end
end
