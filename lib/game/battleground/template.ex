defmodule ThistleTea.Game.Battleground.Template do
  @moduledoc false

  defstruct [
    :type_id,
    :map_id,
    :min_players_per_team,
    :max_players_per_team,
    :min_level,
    :max_level,
    :alliance_start,
    :horde_start,
    :alliance_graveyard,
    :horde_graveyard,
    :alliance_win_spell,
    :alliance_lose_spell,
    :horde_win_spell,
    :horde_lose_spell
  ]
end
