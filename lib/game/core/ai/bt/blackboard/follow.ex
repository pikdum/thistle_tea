defmodule ThistleTea.Game.Core.AI.BT.Blackboard.Follow do
  @moduledoc false

  @enforce_keys [:guid, :distance, :angle]
  defstruct [:guid, :distance, :angle]
end
