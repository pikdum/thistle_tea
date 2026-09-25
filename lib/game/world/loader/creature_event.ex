defmodule ThistleTea.Game.World.Loader.CreatureEvent do
  @moduledoc "Preloads patch-selected world-event creature variants and their equipment and spells."

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.GameEvent.CreatureData
  alias ThistleTea.Game.World.Loader.CreatureArchetype
  alias ThistleTea.Game.World.Loader.Item
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Loader.Spell

  @supported_patch 10
  @fields [:guid, :patch, :event, :entry_id, :display_id, :equipment_id, :spell_start, :spell_end]

  def init do
    case :ets.whereis(__MODULE__) do
      :undefined -> :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true])
      table -> table
    end
  end

  def rows do
    from(row in "game_event_creature_data", where: row.patch <= @supported_patch, select: map(row, ^@fields))
    |> Mangos.Repo.all()
    |> select_patches()
  end

  def select_patches(rows) do
    rows
    |> Enum.sort_by(& &1.patch, :desc)
    |> Enum.uniq_by(&{&1.guid, &1.event})
    |> Enum.sort_by(&{&1.guid, &1.event})
  end

  def load_all do
    rows = rows()
    archetypes = rows |> Enum.map(& &1.entry_id) |> Enum.filter(&(&1 > 0)) |> Enum.uniq() |> CreatureArchetype.load()
    equipment = load_equipment(rows)

    spellbook =
      rows
      |> Enum.flat_map(&[&1.spell_start, &1.spell_end])
      |> Enum.filter(&(&1 > 0))
      |> Enum.uniq()
      |> Map.new(&{&1, Spell.load(&1)})
      |> Map.reject(fn {_id, spell} -> is_nil(spell) end)

    definitions =
      Enum.group_by(rows, & &1.guid, fn row ->
        %CreatureData{
          event: row.event,
          entry: row.entry_id,
          archetypes: Map.get(archetypes, row.entry_id, []),
          model: if(row.display_id > 0, do: ModelGeometry.get(row.display_id)),
          equipment: if(row.equipment_id != 0, do: Map.get(equipment, row.equipment_id, [])),
          spell_start: row.spell_start,
          spell_end: row.spell_end,
          spellbook: Map.take(spellbook, Enum.filter([row.spell_start, row.spell_end], &(&1 > 0)))
        }
      end)

    :ets.insert(__MODULE__, Map.to_list(definitions))
    :ok
  end

  def get(guid) when is_integer(guid) and guid > 0 do
    case :ets.lookup(__MODULE__, guid) do
      [{^guid, definitions}] -> definitions
      [] -> []
    end
  end

  def get(_guid), do: []

  defp load_equipment(rows) do
    ids = rows |> Enum.map(& &1.equipment_id) |> Enum.filter(&(&1 > 0)) |> Enum.uniq()

    from(row in Mangos.CreatureEquipTemplate, where: row.entry in ^ids and row.probability > 0)
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.entry, fn row ->
      items = Enum.map([row.item1, row.item2, row.item3], &Item.get_template/1)
      {row.probability, items}
    end)
  end
end
