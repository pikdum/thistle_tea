defmodule ThistleTea.Game.Entity.Logic.Talents do
  @moduledoc """
  Talent points and learn validation ported from VMangos Player::LearnTalent.
  Spent points are always derived from the known talent rank spells in the
  spellbook — there is no separate counter to drift — and the unspent total
  is written to the client's character-points field through `sync_points/1`.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Talent, as: TalentData
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  @points_per_tier 5

  def total_points(level) when is_integer(level) and level > 9, do: level - 9
  def total_points(_level), do: 0

  def spent_points(spell_ids) when is_list(spell_ids) do
    spell_ids
    |> talent_ranks()
    |> Enum.reduce(0, fn {_talent_id, {_tab_id, rank_index}}, total -> total + rank_index + 1 end)
  end

  def spent_points(_spell_ids), do: 0

  def spent_in_tab(spell_ids, tab_id) when is_list(spell_ids) do
    spell_ids
    |> talent_ranks()
    |> Enum.reduce(0, fn
      {_talent_id, {^tab_id, rank_index}}, total -> total + rank_index + 1
      _entry, total -> total
    end)
  end

  def spent_in_tab(_spell_ids, _tab_id), do: 0

  def unspent(%Character{unit: %{level: level}, internal: %{spells: spell_ids}}) do
    max(total_points(level || 1) - spent_points(spell_ids || []), 0)
  end

  def unspent(_character), do: 0

  def sync_points(%Character{player: player} = character) do
    points = unspent(character)

    if player.character_points1 == points do
      character
    else
      Core.mark_broadcast_update(%{character | player: %{player | character_points1: points}})
    end
  end

  def known_talent_spell_ids(spell_ids) when is_list(spell_ids) do
    Enum.filter(spell_ids, &TalentLoader.by_spell/1)
  end

  def known_talent_spell_ids(_spell_ids), do: []

  def validate(%Character{unit: %{class: class}, internal: %{spells: spell_ids}} = character, talent_id, requested_rank)
      when is_integer(talent_id) and is_integer(requested_rank) do
    spell_ids = spell_ids || []

    with %TalentData{} = talent <- TalentLoader.get(talent_id),
         true <- talent.tab_id in TalentLoader.tab_ids(class),
         spell_id when is_integer(spell_id) <- Enum.at(talent.rank_spell_ids, requested_rank),
         current when current <= requested_rank <- known_rank(spell_ids, talent),
         true <- unspent(character) >= requested_rank - current + 1,
         true <- spent_in_tab(spell_ids, talent.tab_id) >= talent.tier * @points_per_tier,
         true <- prerequisite_met?(spell_ids, talent),
         true <- required_spell_known?(spell_ids, talent) do
      {:ok, spell_id}
    else
      _failed -> :error
    end
  end

  def validate(_character, _talent_id, _requested_rank), do: :error

  defp known_rank(spell_ids, %TalentData{rank_spell_ids: ranks}) do
    ranks
    |> Enum.with_index()
    |> Enum.reduce(0, fn {spell_id, index}, known ->
      if spell_id in spell_ids, do: max(known, index + 1), else: known
    end)
  end

  defp prerequisite_met?(spell_ids, %TalentData{depends_on: depends_on, depends_on_rank: depends_on_rank})
       when is_integer(depends_on) do
    case TalentLoader.get(depends_on) do
      %TalentData{rank_spell_ids: ranks} ->
        ranks
        |> Enum.drop(depends_on_rank)
        |> Enum.any?(&(&1 in spell_ids))

      _missing ->
        true
    end
  end

  defp prerequisite_met?(_spell_ids, _talent), do: true

  defp required_spell_known?(spell_ids, %TalentData{required_spell_id: required}) when is_integer(required) do
    required in spell_ids
  end

  defp required_spell_known?(_spell_ids, _talent), do: true

  defp talent_ranks(spell_ids) do
    Enum.reduce(spell_ids, %{}, fn spell_id, acc ->
      case TalentLoader.by_spell(spell_id) do
        {talent_id, tab_id, rank_index} -> Map.update(acc, talent_id, {tab_id, rank_index}, &best_rank(&1, rank_index))
        _not_talent -> acc
      end
    end)
  end

  defp best_rank({tab_id, best}, rank_index), do: {tab_id, max(best, rank_index)}
end
