defmodule ThistleTea.Game.Entity.Data.Component.Internal.Trap do
  @moduledoc false
  defstruct [:owner_guid, :spell_id, :radius, :charges, :start_delay_ms]
end
