defmodule ThistleTea.Game.Entity.Logic.Condition.InstanceDataSnapshot do
  @moduledoc false

  @enforce_keys [:world, :status]
  defstruct [:world, :status, :script_name, fields: %{}]
end
