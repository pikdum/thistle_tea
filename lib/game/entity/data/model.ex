defmodule ThistleTea.Game.Entity.Data.Model do
  @moduledoc "A display's scale and geometry, with dimensions normalized to object scale one."

  defstruct [:display_id, :equipment, scale: 1.0, bounding_radius: 0.389, combat_reach: 1.5, height: 2.0]
end
