defmodule ThistleTea.Game.Spell.Area do
  @moduledoc "Pure location, quest, race, gender, and aura requirements for a spell."

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Spell

  defstruct [
    :spell_id,
    area_id: 0,
    quest_start: 0,
    quest_end: 0,
    aura_spell: 0,
    race_mask: 0,
    gender: 2,
    quest_start_active?: false,
    autocast?: false
  ]

  defmodule Context do
    @moduledoc "Caster location and optional controlling player facts."
    defstruct [:zone_id, :area_id, :player]
  end

  def player(%Character{unit: unit, player: player}) when not is_nil(player) do
    %Subject{
      kind: :player,
      race: unit.race,
      gender: unit.gender,
      quest_log: player.quest_log,
      rewarded_quests: player.rewarded_quests,
      aura_ids: MapSet.new(unit.auras || [], fn %Holder{spell: %Spell{id: id}} -> id end)
    }
  end

  def player(_entity), do: nil

  def restricted?(%Spell{area_rules: rules}), do: rules != []

  def validate(%Spell{area_rules: []}, _context), do: :ok

  def validate(%Spell{area_rules: rules}, context) do
    if allowed?(rules, context), do: :ok, else: {:error, :requires_area}
  end

  def allowed?([], _context), do: true
  def allowed?(rules, context), do: Enum.any?(rules, &matches?(&1, context))

  def matches?(%__MODULE__{} = rule, %Context{} = context) do
    (rule.area_id == 0 or rule.area_id in [context.zone_id, context.area_id]) and
      player_matches?(rule, context.player)
  end

  def matches?(%__MODULE__{} = rule, nil), do: matches?(rule, %Context{})

  def player_matches?(%__MODULE__{} = rule, %Subject{kind: :player} = player) do
    gender_matches?(rule.gender, player.gender) and race_matches?(rule.race_mask, player.race) and
      start_matches?(rule, player) and end_matches?(rule.quest_end, player) and
      aura_matches?(rule.aura_spell, player.aura_ids)
  end

  def player_matches?(%__MODULE__{} = rule, _player) do
    rule.gender == 2 and rule.race_mask == 0 and rule.quest_start == 0 and
      rule.quest_end == 0 and rule.aura_spell == 0
  end

  def required_area(%Spell{area_rules: rules}) do
    case Enum.find(rules, &(&1.area_id > 0)) do
      %__MODULE__{area_id: area} -> area
      nil -> 0
    end
  end

  defp gender_matches?(2, _gender), do: true
  defp gender_matches?(gender, gender), do: true
  defp gender_matches?(_required, _actual), do: false

  defp race_matches?(0, _race), do: true
  defp race_matches?(mask, race) when is_integer(race) and race > 0, do: (mask &&& 1 <<< (race - 1)) != 0
  defp race_matches?(_mask, _race), do: false

  defp start_matches?(%__MODULE__{quest_start: 0}, _player), do: true

  defp start_matches?(%__MODULE__{quest_start: quest, quest_start_active?: active?}, player) do
    MapSet.member?(player.rewarded_quests || MapSet.new(), quest) or
      (active? and QuestLog.active?(player.quest_log || %{}, quest))
  end

  defp end_matches?(0, _player), do: true
  defp end_matches?(quest, player), do: not MapSet.member?(player.rewarded_quests || MapSet.new(), quest)

  defp aura_matches?(0, _auras), do: true
  defp aura_matches?(spell, auras), do: MapSet.member?(auras || MapSet.new(), abs(spell)) == spell > 0
end
