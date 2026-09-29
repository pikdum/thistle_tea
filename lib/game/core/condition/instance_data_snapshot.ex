defmodule ThistleTea.Game.Core.Condition.InstanceDataSnapshot do
  @moduledoc false

  @enforce_keys [:world, :status]
  defstruct [:world, :status, :script_name, fields: %{}]
end
