defmodule ThistleTea.Game.Core.Combat.ReactiveWindow do
  @moduledoc false

  @enforce_keys [:target_guid, :expires_at]
  defstruct [:target_guid, :expires_at]
end
