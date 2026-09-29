defmodule ThistleTea.Game.Core.Player.Talents do
  @moduledoc """
  Talent points and learn validation ported from VMangos Player::LearnTalent.
  Every lookup goes through the `TalentCatalog` module passed by the caller.
  Spent points are always derived from the known talent rank spells in the
  spellbook — there is no separate counter to drift — and the unspent total
  is written to the client's character-points field through `sync_points/1`.
  """
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Player.Talent, as: TalentData

  @points_per_tier 5

  def total_points(level) when is_integer(level) and level > 9, do: level - 9
  def total_points(_level), do: 0

  def spent_points(spell_ids, catalog) when is_list(spell_ids) do
    spell_ids
    |> talent_ranks(catalog)
    |> Enum.reduce(0, fn {_talent_id, {_tab_id, rank_index}}, total -> total + rank_index + 1 end)
  end

  def spent_points(%Character{} = character, catalog),
    do: character |> known_talent_spell_ids(catalog) |> spent_points(catalog)

  def spent_points(_spell_ids, _catalog), do: 0

  def spent_in_tab(spell_ids, tab_id, catalog) when is_list(spell_ids) do
    spell_ids
    |> talent_ranks(catalog)
    |> Enum.reduce(0, fn
      {_talent_id, {^tab_id, rank_index}}, total -> total + rank_index + 1
      _entry, total -> total
    end)
  end

  def spent_in_tab(_spell_ids, _tab_id, _catalog), do: 0

  def unspent(%Character{unit: %{level: level}} = character, catalog) do
    max(total_points(level || 1) - spent_points(character, catalog), 0)
  end

  def unspent(_character, _catalog), do: 0

  def sync_points(%Character{player: player} = character, catalog) do
    points = unspent(character, catalog)

    if player.character_points1 == points do
      character
    else
      Entity.mark_broadcast_update(%{character | player: %{player | character_points1: points}})
    end
  end

  def known_talent_spell_ids(spell_ids, catalog) when is_list(spell_ids) do
    Enum.filter(spell_ids, &catalog.by_spell/1)
  end

  def known_talent_spell_ids(%Character{unit: %{class: class}, internal: %{spells: spell_ids}}, catalog) do
    tabs = catalog.tab_ids(class)

    Enum.filter(spell_ids || [], fn spell_id ->
      case catalog.by_spell(spell_id) do
        {_talent, tab, _rank} -> tab in tabs
        _ -> false
      end
    end)
  end

  def known_talent_spell_ids(_spell_ids, _catalog), do: []

  def validate(
        %Character{unit: %{class: class}, internal: %{spells: spell_ids}} = character,
        talent_id,
        requested_rank,
        catalog
      )
      when is_integer(talent_id) and is_integer(requested_rank) do
    spell_ids = spell_ids || []

    with %TalentData{} = talent <- catalog.get(talent_id),
         true <- talent.tab_id in catalog.tab_ids(class),
         spell_id when is_integer(spell_id) <- Enum.at(talent.rank_spell_ids, requested_rank),
         current when current <= requested_rank <- known_rank(spell_ids, talent, catalog),
         true <- unspent(character, catalog) >= requested_rank - current + 1,
         true <- spent_in_tab(spell_ids, talent.tab_id, catalog) >= talent.tier * @points_per_tier,
         true <- prerequisite_met?(spell_ids, talent, catalog),
         true <- required_spell_known?(spell_ids, talent) do
      {:ok, Enum.slice(talent.rank_spell_ids, current..requested_rank)}
    else
      _failed -> :error
    end
  end

  def validate(_character, _talent_id, _requested_rank, _catalog), do: :error

  defp known_rank(spell_ids, %TalentData{id: talent_id}, catalog) do
    Enum.reduce(spell_ids, 0, fn spell_id, known ->
      case catalog.by_spell(spell_id) do
        {^talent_id, _tab_id, rank_index} -> max(known, rank_index + 1)
        _other -> known
      end
    end)
  end

  defp prerequisite_met?(spell_ids, %TalentData{depends_on: depends_on, depends_on_rank: depends_on_rank}, catalog)
       when is_integer(depends_on) do
    case catalog.get(depends_on) do
      %TalentData{} = prerequisite ->
        known_rank(spell_ids, prerequisite, catalog) > depends_on_rank

      _missing ->
        true
    end
  end

  defp prerequisite_met?(_spell_ids, _talent, _catalog), do: true

  defp required_spell_known?(spell_ids, %TalentData{required_spell_id: required}) when is_integer(required) do
    required in spell_ids
  end

  defp required_spell_known?(_spell_ids, _talent), do: true

  defp talent_ranks(spell_ids, catalog) do
    Enum.reduce(spell_ids, %{}, fn spell_id, acc ->
      case catalog.by_spell(spell_id) do
        {talent_id, tab_id, rank_index} -> Map.update(acc, talent_id, {tab_id, rank_index}, &best_rank(&1, rank_index))
        _not_talent -> acc
      end
    end)
  end

  defp best_rank({tab_id, best}, rank_index), do: {tab_id, max(best, rank_index)}
end
