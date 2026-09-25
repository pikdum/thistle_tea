defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Distancing do
  @moduledoc false

  @enforce_keys [:target_guid, :target_position, :destination, :combat?, :victim_guid]
  defstruct [:target_guid, :target_position, :destination, :combat?, :victim_guid, started?: false]
end
