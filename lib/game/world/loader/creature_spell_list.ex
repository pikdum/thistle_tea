defmodule ThistleTea.Game.World.Loader.CreatureSpellList do
  @moduledoc "Loads creature spell lists into shared definitions without fetching DBC spell data."

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.CreatureSpell
  alias ThistleTea.Game.Core.AI.CreatureSpellList

  def load([]), do: %{}

  def load(ids) when is_list(ids) do
    from(list in Mangos.CreatureSpells, where: list.entry in ^Enum.uniq(ids))
    |> Mangos.Repo.all()
    |> Map.new(fn row ->
      spells = row |> Mangos.CreatureSpells.slots() |> Enum.map(&CreatureSpell.build/1) |> Enum.reject(&is_nil/1)
      {row.entry, %CreatureSpellList{id: row.entry, spells: spells}}
    end)
  end
end
