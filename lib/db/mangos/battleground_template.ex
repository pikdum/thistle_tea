defmodule ThistleTea.DB.Mangos.BattlegroundTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "battleground_template" do
    field(:id, :integer)
    field(:patch, :integer)
    field(:min_players_per_team, :integer)
    field(:max_players_per_team, :integer)
    field(:min_level, :integer)
    field(:max_level, :integer)
    field(:alliance_win_spell, :integer)
    field(:alliance_lose_spell, :integer)
    field(:horde_win_spell, :integer)
    field(:horde_lose_spell, :integer)
    field(:alliance_start_location, :integer)
    field(:horde_start_location, :integer)
    field(:player_loot_id, :integer)
  end
end
