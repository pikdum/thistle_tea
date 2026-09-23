defmodule ThistleTea.Game.Entity.Data.Component.Internal.ObjectAction do
  @moduledoc false

  defstruct default_state: 1, auto_close_ms: 0, revision: 0, active?: false, lock_override: nil
end
