defmodule ThistleTea.Game.Core.Travel.HomeBind do
  @moduledoc """
  A character's retained home location, independent of their current world.
  """

  @enforce_keys [:map_id, :area_id, :position]
  defstruct [:map_id, :area_id, :position]
end
