defmodule ThistleTea.Game.Entity.Data.Pvp do
  @moduledoc """
  Player-owned PvP preference, territory rules, and paused countdowns.
  """

  defstruct [
    :updated_at,
    desired?: false,
    enforced?: false,
    free_for_all?: false,
    combat?: false,
    remaining_ms: 0,
    contested_remaining_ms: 0
  ]
end
