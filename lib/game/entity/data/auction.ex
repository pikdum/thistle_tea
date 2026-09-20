defmodule ThistleTea.Game.Entity.Data.Auction do
  @moduledoc """
  An escrowed item and the current bid in one vanilla auction market.
  House rates are captured when the seller creates the listing.
  """

  @enforce_keys [:id, :house, :item, :owner, :owner_account, :start_bid, :buyout, :deposit, :created_at, :expires_at]
  defstruct @enforce_keys ++ [bidder: 0, bid: 0, revision: 0]
end
