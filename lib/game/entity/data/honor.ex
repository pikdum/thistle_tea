defmodule ThistleTea.Game.Entity.Data.Honor do
  @moduledoc """
  Runtime honor ledger with daily contribution totals, repeated victims,
  lifetime kills, and the latest settled weekly ranking.
  """

  alias ThistleTea.Game.Entity.Data.Honor.Day

  defstruct days: %{},
            rank_points: 0.0,
            highest_rank: 0,
            lifetime_honorable_kills: 0,
            lifetime_dishonorable_kills: 0,
            last_week: %Day{},
            last_standing: 0,
            last_settled_week: nil
end
