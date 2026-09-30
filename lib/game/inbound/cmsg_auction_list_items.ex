defmodule ThistleTea.Game.Inbound.CmsgAuctionListItems do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_AUCTION_LIST_ITEMS

  alias ThistleTea.Game.Core.Auction.Query
  alias ThistleTea.Game.World.Entity.Player.Auction

  defstruct [:auctioneer, :query]
  @impl ClientMessage
  def from_binary(<<auctioneer::little-size(64), offset::little-size(32), rest::binary>>) do
    {:ok, name, rest} = BinaryUtils.parse_string(rest)

    <<minimum, maximum, slot::little-size(32), class::little-size(32), subclass::little-size(32),
      quality::little-size(32), usable>> = rest

    %__MODULE__{
      auctioneer: auctioneer,
      query: %Query{
        offset: offset,
        name: name,
        level_min: minimum,
        level_max: maximum,
        inventory_type: slot,
        class: class,
        subclass: subclass,
        quality: quality,
        usable?: usable != 0
      }
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Auction.search(state, message)
end
