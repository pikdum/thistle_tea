defmodule ThistleTea.Game.World.Loader.CreatureSpellList do
  @moduledoc """
  Loads creature spell lists into shared definitions without fetching DBC
  spell data, attaching each entry's `creature_spells_scripts` steps.
  """

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.CreatureSpell
  alias ThistleTea.Game.Core.AI.CreatureSpellList
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader

  def load([]), do: %{}

  def load(ids) when is_list(ids) do
    lists =
      from(list in Mangos.CreatureSpells, where: list.entry in ^Enum.uniq(ids))
      |> Mangos.Repo.all()
      |> Map.new(fn row ->
        spells = row |> Mangos.CreatureSpells.slots() |> Enum.map(&CreatureSpell.build/1) |> Enum.reject(&is_nil/1)
        {row.entry, spells}
      end)

    scripts =
      lists
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1.script_id)
      |> Enum.filter(&(&1 > 0))
      |> then(&ScriptLoader.load_by_ids(Mangos.CreatureSpellsScript, &1))

    Map.new(lists, fn {entry, spells} ->
      spells = Enum.map(spells, &%{&1 | script: Map.get(scripts, &1.script_id, [])})
      {entry, %CreatureSpellList{id: entry, spells: spells}}
    end)
  end
end
