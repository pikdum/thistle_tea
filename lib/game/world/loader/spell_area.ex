defmodule ThistleTea.Game.World.Loader.SpellArea do
  @moduledoc "Preloads location-dependent spell rules and their automatic aura candidates."

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.SpellArea
  alias ThistleTea.Game.Spell.Area

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    SpellArea |> Mangos.Repo.all() |> load()
  end

  def load(rows, table \\ __MODULE__) do
    rules = rows |> Enum.map(&translate/1) |> Enum.sort()
    :ets.delete_all_objects(table)
    :ets.insert(table, {:autocast, Enum.filter(rules, & &1.autocast?)})
    Enum.each(Enum.group_by(rules, & &1.spell_id), &:ets.insert(table, &1))
    :ok
  end

  def get(spell_id, table \\ __MODULE__) do
    case :ets.lookup(table, spell_id) do
      [{^spell_id, rules}] -> rules
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  def autocast_rules(table \\ __MODULE__), do: get(:autocast, table)

  def translate(%SpellArea{} = row) do
    %Area{
      spell_id: row.spell,
      area_id: row.area,
      quest_start: row.quest_start,
      quest_start_active?: row.quest_start_active != 0,
      quest_end: row.quest_end,
      aura_spell: row.aura_spell,
      race_mask: row.racemask,
      gender: row.gender,
      autocast?: row.autocast != 0
    }
  end
end
