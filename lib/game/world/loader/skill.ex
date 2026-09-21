defmodule ThistleTea.Game.World.Loader.Skill do
  @moduledoc """
  Startup catalog of skill categories, race/class flags, and associated spells.
  Runtime training and abandonment read the catalog without database queries.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Logic.Skills

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _table -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    load(DBC.all(SkillLine), DBC.all(SkillRaceClassInfo), DBC.all(SkillLineAbility), table)
  end

  def load(lines, infos, abilities, table \\ __MODULE__) do
    Enum.each(lines, &:ets.insert(table, {{:category, &1.id}, &1.category}))
    cache_groups(infos, :skill_line, :info, table)
    cache_groups(abilities, :skill_line, :abilities, table)
    cache_groups(abilities, :spell, :spell_skills, table)
    :ok
  end

  def initial_skills(spell_ids, race, class, level, table \\ __MODULE__)

  def initial_skills(spell_ids, race, class, level, table) when is_list(spell_ids) do
    spell_ids
    |> Enum.flat_map(&lookup(table, {:spell_skills, &1}, []))
    |> Enum.filter(&(&1.acquire_method == 2 and fits?(&1, race, class)))
    |> Enum.map(& &1.skill_line)
    |> Enum.uniq()
    |> Enum.flat_map(&build_entry(&1, race, class, level, table))
    |> Map.new()
    |> Skills.with_slots()
  end

  def initial_skills(_spell_ids, _race, _class, _level, _table), do: %{}

  def reward_spells(skill_id, value, race, class, table \\ __MODULE__) do
    table
    |> lookup({:abilities, skill_id}, [])
    |> Enum.filter(&(&1.acquire_method == 1 and &1.min_skill_line_rank <= value and fits?(&1, race, class)))
    |> Enum.map(& &1.spell)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def spells(skill_id, table \\ __MODULE__) do
    table |> lookup({:abilities, skill_id}, []) |> Enum.map(& &1.spell) |> Enum.uniq() |> Enum.sort()
  end

  def recipe(spell_id, table \\ __MODULE__) do
    table
    |> lookup({:spell_skills, spell_id}, [])
    |> Enum.find(fn row ->
      lookup(table, {:category, row.skill_line}, nil) in [9, 11] and
        is_integer(row.trivial_skill_line_rank_low) and is_integer(row.trivial_skill_line_rank_high)
    end)
    |> case do
      nil ->
        nil

      row ->
        %{skill_id: row.skill_line, yellow: row.trivial_skill_line_rank_low, gray: row.trivial_skill_line_rank_high}
    end
  end

  def unlearnable?(skill_id, race, class, table \\ __MODULE__) do
    case race_class_info(skill_id, race, class, table) do
      %{flags: flags} -> (flags &&& 0x20) != 0
      nil -> false
    end
  end

  defp build_entry(id, race, class, level, table) do
    with %{skill_tier: 0, flags: flags} <- race_class_info(id, race, class, table),
         category when is_integer(category) <- lookup(table, {:category, id}, nil) do
      [{id, Skills.new_entry(range(category), (flags &&& 0x10) != 0, level)}]
    else
      _skip -> []
    end
  end

  defp race_class_info(id, race, class, table) do
    table |> lookup({:info, id}, []) |> Enum.find(&fits?(&1, race, class))
  end

  defp fits?(row, race, class) do
    (row.race_mask == 0 or (row.race_mask &&& 1 <<< (race - 1)) != 0) and
      (row.class_mask == 0 or (row.class_mask &&& 1 <<< (class - 1)) != 0)
  end

  defp cache_groups(rows, field, kind, table) do
    rows
    |> Enum.group_by(&Map.fetch!(&1, field), &Map.from_struct/1)
    |> Enum.each(fn {id, values} -> :ets.insert(table, {{kind, id}, values}) end)
  end

  defp lookup(table, key, default) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      _missing -> default
    end
  end

  defp range(8), do: :mono
  defp range(10), do: :language
  defp range(_category), do: :level
end
