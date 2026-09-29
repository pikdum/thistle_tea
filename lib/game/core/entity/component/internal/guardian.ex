defmodule ThistleTea.Game.Core.Entity.Component.Internal.Guardian do
  @moduledoc """
  Autonomous guardian lifetime.
  """

  defstruct [:expires_at, :expiration_spell_id, :cooldown_started_at, corpse_delay_ms: 15_000]
end
