defmodule ThistleTea.Game.Entity.Data.Auction.Change do
  @moduledoc """
  A proposed market transition. Inventory and money planning must succeed
  before the boundary commits the book, escrow, receipt, and deliveries.
  """

  @enforce_keys [:book]
  defstruct @enforce_keys ++ [auction: nil, action: nil, cost: 0, deliveries: [], notices: []]
end
