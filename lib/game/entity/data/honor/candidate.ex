defmodule ThistleTea.Game.Entity.Data.Honor.Candidate do
  @moduledoc false
  @enforce_keys [:guid, :team, :level]
  defstruct [:guid, :team, :level, honorable_kills: 0, contribution: 0.0, rank_points: 0.0]
end
