defmodule ThistleTea.Game.Entity.Data.Honor.Award do
  @moduledoc false
  @enforce_keys [:type, :points]
  defstruct [:type, :points, :victim_key, victim_guid: 0, victim_rank: 0]
end
