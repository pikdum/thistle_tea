defmodule ThistleTea.Game.Battleground.Player do
  @moduledoc false
  @enforce_keys [:guid, :name, :team]
  defstruct [
    :guid,
    :name,
    :team,
    :return_to,
    status: :invited,
    killing_blows: 0,
    honorable_kills: 0,
    deaths: 0,
    bonus_honor: 0,
    flag_captures: 0,
    flag_returns: 0,
    bases_assaulted: 0,
    bases_defended: 0
  ]
end
