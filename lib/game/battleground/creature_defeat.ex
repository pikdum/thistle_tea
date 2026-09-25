defmodule ThistleTea.Game.Battleground.CreatureDefeat do
  @moduledoc "A defeated creature incarnation, its battleground event bindings, and the player responsible."

  @enforce_keys [:victim_guid, :entry, :db_guid, :incarnation_id, :killer_guid, :bindings]
  defstruct [:victim_guid, :entry, :db_guid, :incarnation_id, :killer_guid, :bindings]
end
