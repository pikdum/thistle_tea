defmodule ThistleTea.Game.Entity.Data.Auction.Receipt do
  @moduledoc """
  A committed auction transaction awaiting projection by its player owner.
  The identifier prevents recovery from applying an older inventory twice.
  """

  @enforce_keys [:id, :guid, :changes, :old_counts, :outgoing, :action, :auction]
  defstruct @enforce_keys
end
