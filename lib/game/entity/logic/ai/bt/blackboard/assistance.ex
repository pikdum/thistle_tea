defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Assistance do
  @moduledoc false

  @enforce_keys [:helper_guid, :enemy_guid, :destination]
  defstruct [:helper_guid, :enemy_guid, :destination, :wait_until, requested?: false]
end
