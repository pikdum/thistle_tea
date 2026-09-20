defmodule ThistleTea.Game.Network.Message.SmsgTradeStatusExtended do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_TRADE_STATUS_EXTENDED

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Item

  defstruct other?: true, money: 0, spell_id: 0, items: %{}

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<if(message.other?, do: 1, else: 0), 7::little-size(32), 7::little-size(32), message.money::little-size(32),
      message.spell_id::little-size(32)>> <>
      Enum.map_join(0..6, fn slot -> <<slot>> <> item_binary(Map.get(message.items, slot)) end)
  end

  defp item_binary(nil), do: <<0::size(480)>>

  defp item_binary(%Item{} = item) do
    template = Item.template(item)

    <<item.object.entry::little-size(32), template.display_id::little-size(32), item.item.stack_count::little-size(32),
      if((number(item.item.flags) &&& 8) == 0, do: 0, else: 1)::little-size(32),
      number(item.item.gift_creator)::little-size(64), number(item.item.enchantment) &&& 0xFFFFFFFF::little-size(32),
      number(item.item.creator)::little-size(64), number(item.item.spell_charges) &&& 0xFFFFFFFF::little-size(32),
      number(item.item.property_seed)::little-size(32), number(item.item.random_properties_id)::little-size(32),
      template.lockid::little-size(32), number(item.item.max_durability)::little-size(32),
      number(item.item.durability)::little-size(32)>>
  end

  defp number(value), do: value || 0
end
