defmodule ThistleTea.Game.Entity.Data.ItemDuration do
  @moduledoc """
  An item's remaining play-time budget and its active monotonic deadline.
  A nil deadline pauses the budget while the owner is offline.
  """
  @enforce_keys [:remaining_ms]
  defstruct @enforce_keys ++ [expires_at: nil]
end
