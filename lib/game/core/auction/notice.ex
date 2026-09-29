defmodule ThistleTea.Game.Core.Auction.Notice do
  @moduledoc false

  @enforce_keys [:recipient, :kind, :auction]
  defstruct @enforce_keys
end
