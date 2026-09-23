defmodule ThistleTea.Game.Battleground.Result do
  @moduledoc "A pure match transition and the boundary effects and timers it requests."
  @enforce_keys [:match]
  defstruct [:match, effects: [], timers: []]
end
