defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation do
  @moduledoc false

  @enforce_keys [:guid]
  defstruct [
    :guid,
    :position,
    :grounded_position,
    :distance,
    :metadata,
    moving?: false,
    line_of_sight?: true
  ]
end
