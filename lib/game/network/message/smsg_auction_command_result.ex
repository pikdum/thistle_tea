defmodule ThistleTea.Game.Network.Message.SmsgAuctionCommandResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AUCTION_COMMAND_RESULT

  @actions %{started: 0, removed: 1, bid_placed: 2}
  @errors %{
    ok: 0,
    inventory: 1,
    database: 2,
    not_enough_money: 3,
    item_not_found: 4,
    higher_bid: 5,
    bid_increment: 7,
    bid_own: 10,
    restricted: 13
  }
  defstruct auction_id: 0, action: :started, error: :ok, inventory_error: 0, bidder: 0, bid: 0, increment: 0
  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.auction_id::little-size(32), Map.fetch!(@actions, message.action)::little-size(32),
      Map.fetch!(@errors, message.error)::little-size(32)>> <> details(message)
  end

  defp details(%__MODULE__{error: :ok, action: :bid_placed, increment: increment}), do: <<increment::little-size(32)>>
  defp details(%__MODULE__{error: :inventory, inventory_error: error}), do: <<error::little-size(32)>>

  defp details(%__MODULE__{error: :higher_bid} = message) do
    <<message.bidder::little-size(64), message.bid::little-size(32), message.increment::little-size(32)>>
  end

  defp details(_message), do: <<>>
end
