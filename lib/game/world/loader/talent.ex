defmodule ThistleTea.Game.World.Loader.Talent do
  @moduledoc """
  Preloads the talent trees from the Talent and TalentTab DBCs: per-class
  tab lists, per-talent tier/column/rank/prerequisite data, and a reverse
  spell-to-talent index so spent points can be derived from the spellbook.
  """
  import Bitwise, only: [<<<: 2, &&&: 2]
  import Ecto.Query

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Talent, as: TalentData

  @classes 1..11
  @learn_spell_effect 36
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    tabs = DBC.all(TalentTab)
    talent_rows = DBC.all(Talent)

    learned_spell_ids_by_parent =
      talent_rows
      |> Enum.flat_map(&rank_spell_ids/1)
      |> learned_spell_ids_by_parent()

    successor_by_spell =
      DBC.all(
        from(s in SkillLineAbility,
          where: s.spell > 0 and s.superseded_by > 0,
          select: {s.spell, s.superseded_by}
        )
      )
      |> Map.new()

    Enum.each(@classes, fn class ->
      class_mask = 1 <<< (class - 1)

      tab_ids =
        tabs
        |> Enum.filter(&((&1.class_mask &&& class_mask) != 0))
        |> Enum.sort_by(& &1.order_index)
        |> Enum.map(& &1.id)

      :ets.insert(__MODULE__, {{:tabs, class}, tab_ids})
    end)

    Enum.each(talent_rows, fn row ->
      talent = build(row)
      :ets.insert(__MODULE__, {{:talent, talent.id}, talent})

      talent
      |> rank_spell_variants(successor_by_spell)
      |> cache_spell_lineage(talent)

      Enum.each(talent.rank_spell_ids, fn spell_id ->
        :ets.insert(
          __MODULE__,
          {{:dependent_spells, spell_id}, Map.get(learned_spell_ids_by_parent, spell_id, [])}
        )
      end)
    end)

    :ok
  end

  def get(talent_id) when is_integer(talent_id) and talent_id > 0 do
    case :ets.lookup(__MODULE__, {:talent, talent_id}) do
      [{_key, %TalentData{} = talent}] -> talent
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def get(_talent_id), do: nil

  def tab_ids(class) when is_integer(class) do
    case :ets.lookup(__MODULE__, {:tabs, class}) do
      [{_key, tab_ids}] -> tab_ids
      _ -> []
    end
  rescue
    ArgumentError -> []
  end

  def tab_ids(_class), do: []

  def by_spell(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, {:by_spell, spell_id}) do
      [{_key, entry}] -> entry
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def by_spell(_spell_id), do: nil

  def chain(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, {:chain, spell_id}) do
      [{_key, chain}] -> chain
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def chain(_spell_id), do: nil

  def superseded_by_map(spell_ids) when is_list(spell_ids) do
    spell_ids
    |> Enum.flat_map(fn spell_id ->
      case :ets.lookup(__MODULE__, {:superseded_by, spell_id}) do
        [{_key, next_spell_id}] -> [{spell_id, next_spell_id}]
        _ -> []
      end
    end)
    |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  def superseded_by_map(_spell_ids), do: %{}

  def dependent_spell_ids(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, {:dependent_spells, spell_id}) do
      [{_key, spell_ids}] -> spell_ids
      _ -> []
    end
  rescue
    ArgumentError -> []
  end

  def dependent_spell_ids(_spell_id), do: []

  defp build(row) do
    %TalentData{
      id: row.id,
      tab_id: row.tab,
      tier: row.tier || 0,
      column: row.column_index || 0,
      depends_on: positive(row.prereq_talents_0),
      depends_on_rank: row.prereq_ranks_0 || 0,
      required_spell_id: positive(row.required_spell),
      rank_spell_ids: rank_spell_ids(row)
    }
  end

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp rank_spell_ids(row) do
    [row.spell_rank_0, row.spell_rank_1, row.spell_rank_2, row.spell_rank_3, row.spell_rank_4]
    |> Enum.take_while(&(is_integer(&1) and &1 > 0))
  end

  defp learned_spell_ids_by_parent([]), do: %{}

  defp learned_spell_ids_by_parent(spell_ids) do
    DBC.all(
      from(s in Spell,
        where: s.id in ^spell_ids,
        select: %{
          id: s.id,
          effects: [
            {s.effect_0, s.effect_trigger_spell_0},
            {s.effect_1, s.effect_trigger_spell_1},
            {s.effect_2, s.effect_trigger_spell_2}
          ]
        }
      )
    )
    |> Map.new(fn row ->
      learned_spell_ids =
        for {@learn_spell_effect, spell_id} <- row.effects,
            is_integer(spell_id) and spell_id > 0,
            do: spell_id

      {row.id, learned_spell_ids}
    end)
  end

  defp rank_spell_variants(%TalentData{rank_spell_ids: rank_spell_ids}, successor_by_spell) do
    canonical_ids = MapSet.new(rank_spell_ids)

    Enum.map(rank_spell_ids, fn spell_id ->
      [spell_id | successors(spell_id, successor_by_spell, canonical_ids, MapSet.new([spell_id]))]
    end)
  end

  defp successors(spell_id, successor_by_spell, canonical_ids, visited) do
    case Map.get(successor_by_spell, spell_id) do
      next_spell_id when is_integer(next_spell_id) and next_spell_id > 0 ->
        if MapSet.member?(canonical_ids, next_spell_id) or MapSet.member?(visited, next_spell_id) do
          []
        else
          [
            next_spell_id
            | successors(next_spell_id, successor_by_spell, canonical_ids, MapSet.put(visited, next_spell_id))
          ]
        end

      _ ->
        []
    end
  end

  defp cache_spell_lineage(rank_variants, %TalentData{} = talent) do
    Enum.with_index(rank_variants)
    |> Enum.each(fn {spell_ids, rank_index} ->
      Enum.each(spell_ids, fn spell_id ->
        :ets.insert(__MODULE__, {{:by_spell, spell_id}, {talent.id, talent.tab_id, rank_index}})
      end)
    end)

    spell_ids = List.flatten(rank_variants)
    first_spell = List.first(spell_ids)

    spell_ids
    |> Enum.with_index()
    |> Enum.each(fn {spell_id, index} ->
      previous_spell = if index > 0, do: Enum.at(spell_ids, index - 1)

      :ets.insert(
        __MODULE__,
        {{:chain, spell_id}, %{first_spell: first_spell, rank: index + 1, prev_spell: previous_spell, req_spell: nil}}
      )

      case Enum.at(spell_ids, index + 1) do
        next_spell_id when is_integer(next_spell_id) ->
          :ets.insert(__MODULE__, {{:superseded_by, spell_id}, next_spell_id})

        _ ->
          :ok
      end
    end)
  end
end
