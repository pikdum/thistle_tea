defmodule ThistleTea.Game.Entity.Data.Component.Internal.Fishing do
  @moduledoc false

  defstruct [
    :owner_guid,
    :area_id,
    :zone_id,
    :loot_id,
    :uses_left,
    :bite_delay_ms,
    ready?: false,
    consumed?: false
  ]
end
