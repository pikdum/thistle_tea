defmodule ThistleTea.Game.Entity.Logic.Condition.Reason do
  @moduledoc false

  defstruct [:entry, :type, :capability]

  @type t :: %__MODULE__{entry: integer(), type: atom() | tuple(), capability: term()}
end
