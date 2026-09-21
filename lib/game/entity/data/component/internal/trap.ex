defmodule ThistleTea.Game.Entity.Data.Component.Internal.Trap do
  @moduledoc false
  defstruct [
    :owner_guid,
    :spell_id,
    :radius,
    :charges,
    :start_delay_ms,
    :ready_at,
    cooldown_ms: 4_000,
    depleted?: false
  ]
end
