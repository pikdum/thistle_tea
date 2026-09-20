defmodule ThistleTea.Game.Entity.Data.Auction.Notice do
  @moduledoc false

  @enforce_keys [:recipient, :kind, :auction]
  defstruct @enforce_keys
end
