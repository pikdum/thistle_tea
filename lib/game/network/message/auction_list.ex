defmodule ThistleTea.Game.Network.Message.AuctionList do
  @moduledoc "Shared vanilla auction list encoding with one 64-byte row per item."
  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Entity.Data.Auction
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Auction, as: AuctionLogic

  def to_binary(auctions, total, now) do
    IO.iodata_to_binary([
      <<length(auctions)::little-size(32)>>,
      Enum.map(auctions, &entry(&1, now)),
      <<total::little-size(32)>>
    ])
  end

  defp entry(%Auction{item: item} = auction, now) do
    enchantment = band(item.item.enchantment || 0, 0xFFFFFFFF)
    remaining = auction.expires_at |> Kernel.-(now) |> max(0) |> min(0x7FFFFFFF)
    increment = if auction.bid > 0, do: AuctionLogic.increment(auction), else: 0

    <<auction.id::little-size(32), item.object.entry::little-size(32), enchantment::little-size(32),
      item.item.random_properties_id || 0::little-size(32), item.item.property_seed || 0::little-size(32),
      item.item.stack_count::little-size(32), Item.spell_charge(item, 1)::little-size(32),
      auction.owner::little-size(64), auction.start_bid::little-size(32), increment::little-size(32),
      auction.buyout::little-size(32), remaining::little-size(32), auction.bidder::little-size(64),
      auction.bid::little-size(32)>>
  end
end
