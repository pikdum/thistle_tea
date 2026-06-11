defmodule ThistleTea.Game.Network.Message.SmsgListInventory do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LIST_INVENTORY

  defstruct [:vendor_guid, items: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{vendor_guid: vendor_guid, items: []}) do
    <<vendor_guid::little-size(64), 0, 0>>
  end

  def to_binary(%__MODULE__{vendor_guid: vendor_guid, items: items}) do
    items_binary =
      Enum.map_join(items, fn %{index: index, template: template, max_count: max_count} ->
        available = if max_count <= 0, do: 0xFFFFFFFF, else: max_count

        <<index::little-size(32), template.entry::little-size(32), template.display_id::little-size(32),
          available::little-size(32), template.buy_price::little-size(32), template.max_durability::little-size(32),
          template.buy_count::little-size(32)>>
      end)

    <<vendor_guid::little-size(64), Enum.count(items)>> <> items_binary
  end
end
