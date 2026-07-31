defmodule ThistleTea.DB.Mangos.CreatureOnkillReputation do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "creature_onkill_reputation" do
    field(:creature_id, :integer)
    field(:patch, :integer)
    field(:reward_faction_1, :integer, source: :RewOnKillRepFaction1)
    field(:reward_faction_2, :integer, source: :RewOnKillRepFaction2)
    field(:max_rank_1, :integer, source: :MaxStanding1)
    field(:team_award_1, :integer, source: :IsTeamAward1)
    field(:reward_value_1, :integer, source: :RewOnKillRepValue1)
    field(:max_rank_2, :integer, source: :MaxStanding2)
    field(:team_award_2, :integer, source: :IsTeamAward2)
    field(:reward_value_2, :integer, source: :RewOnKillRepValue2)
    field(:team_dependent, :integer, source: :TeamDependent)
  end
end
