defmodule ThistleTea.Game.Entity.Data.Auction.Delivery do
  @moduledoc """
  A uniquely identified auction settlement to deliver through the Post Office.
  The attachment, when present, is already assigned to its receiving owner.
  """

  @enforce_keys [:key, :attrs]
  defstruct @enforce_keys ++ [item: nil]
end
