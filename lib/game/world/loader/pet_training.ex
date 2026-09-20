defmodule ThistleTea.Game.World.Loader.PetTraining do
  @moduledoc """
  Startup catalogue of pet abilities and family skills. Training reads only ETS.
  Vanilla's training cost occupies the converter's num_skills_up column.
  """

  import Ecto.Query

  alias ThistleTea.DBC
  alias ThistleTea.DBC.CreatureFamily
  alias ThistleTea.Game.Entity.Data.PetAbility
  alias ThistleTea.Game.Spell, as: SpellData
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _ -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    family_rows = DBC.all(CreatureFamily)
    families = Map.new(family_rows, &{&1.id, &1.training_skill})
    skills = Enum.uniq([270 | Enum.flat_map(family_rows, &[&1.training_skill, &1.secondary_skill])])
    rows = DBC.all(from(ability in SkillLineAbility, where: ability.skill_line in ^skills))
    spells = rows |> Enum.map(& &1.spell) |> SpellLoader.build_spellbook()
    abilities = build(rows, spells)

    :ets.insert(table, [{:abilities, abilities}, {:families, families}])

    Enum.each(family_rows, fn family ->
      passives = family_passives(rows, spells, [family.training_skill, family.secondary_skill])
      :ets.insert(table, {{:family_passives, family.id}, passives})
    end)

    :ok
  end

  def family_passives(rows, spells, skills) do
    ids = for row <- rows, row.skill_line in skills and row.acquire_method == 2, do: row.spell
    spells |> Map.take(ids) |> Map.filter(fn {_id, spell} -> SpellData.attribute?(spell, :passive) end)
  end

  def family_passives(family, table \\ __MODULE__), do: lookup(table, {:family_passives, family})

  def build(rows, spells) do
    predecessors =
      rows
      |> Enum.filter(&(&1.superseded_by > 0 and Map.has_key?(spells, &1.superseded_by)))
      |> Map.new(&{&1.superseded_by, &1.spell})

    rows
    |> Enum.group_by(& &1.spell)
    |> Enum.flat_map(fn {id, entries} ->
      case Map.fetch(spells, id) do
        {:ok, spell} ->
          {first, rank} = lineage(id, predecessors, MapSet.new())
          spell = %{spell | first_in_chain: first, rank: rank}

          [
            {id,
             %PetAbility{spell: spell, skills: Enum.map(entries, & &1.skill_line), cost: hd(entries).training_points}}
          ]

        :error ->
          []
      end
    end)
    |> Map.new()
  end

  defp lineage(id, predecessors, visited) do
    case Map.get(predecessors, id) do
      nil ->
        {id, 1}

      previous ->
        if MapSet.member?(visited, previous) do
          {id, 1}
        else
          {first, rank} = lineage(previous, predecessors, MapSet.put(visited, id))
          {first, rank + 1}
        end
    end
  end

  def abilities(table \\ __MODULE__), do: lookup(table, :abilities)
  def family_skill(family, table \\ __MODULE__), do: Map.get(lookup(table, :families), family)

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      _ -> %{}
    end
  end
end
