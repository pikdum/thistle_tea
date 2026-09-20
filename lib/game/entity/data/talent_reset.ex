defmodule ThistleTea.Game.Entity.Data.TalentReset do
  @moduledoc """
  Retained talent reset history, independent of the current talent allocation.
  """

  defstruct [:last_reset_at, multiplier: 0]
end
