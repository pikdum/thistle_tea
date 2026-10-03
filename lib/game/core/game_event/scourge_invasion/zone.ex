defmodule ThistleTea.Game.Core.GameEvent.ScourgeInvasion.Zone do
  @moduledoc false

  @enforce_keys [
    :name,
    :zone_id,
    :map_id,
    :event,
    :necropolises,
    :mouth,
    :attack_time_variable,
    :remaining_variable,
    :invaded_state,
    :remaining_state
  ]
  defstruct @enforce_keys
end
