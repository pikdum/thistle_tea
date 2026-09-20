defmodule ThistleTea.Game.Battleground.Defeat do
  @moduledoc "A lethal player hit and the participants present when it happened."

  @enforce_keys [:victim_guid, :killer_guid, :position]
  defstruct [:victim_guid, :killer_guid, :position, nearby_guids: [], count_death?: true]
end
