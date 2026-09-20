defmodule ThistleTea.Game.Entity.Data.Auction.House do
  @moduledoc """
  Cached auction-house identity, linked market, and percentage fees.
  Alliance, Horde, and neutral houses each share a separate market in 1.12.
  """

  @enforce_keys [:id, :market, :deposit_percent, :cut_percent]
  defstruct @enforce_keys
end
