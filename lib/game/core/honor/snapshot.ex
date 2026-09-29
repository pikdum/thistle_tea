defmodule ThistleTea.Game.Core.Honor.Snapshot do
  @moduledoc false

  @enforce_keys [:honor, :day, :week_start]
  defstruct [:honor, :day, :week_start]
end
