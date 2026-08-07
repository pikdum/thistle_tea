defmodule ThistleTea.Game.Entity.Data.AreaTriggerTeleport do
  @moduledoc false

  defstruct [
    :id,
    :name,
    :message,
    :required_level,
    :condition,
    :target_map,
    :x,
    :y,
    :z,
    :orientation
  ]
end
