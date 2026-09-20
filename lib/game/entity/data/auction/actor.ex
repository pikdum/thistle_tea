defmodule ThistleTea.Game.Entity.Data.Auction.Actor do
  @moduledoc false

  @enforce_keys [:guid, :account_id, :money]
  defstruct @enforce_keys
end
