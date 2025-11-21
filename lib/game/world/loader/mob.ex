defmodule ThistleTea.Game.World.Loader.Mob do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.System.GameEvent

  def load(cell) do
    events = GameEvent.get_events()

    Mangos.Creature.query_cell(cell, events)
    |> Mangos.Repo.all()
    |> Enum.map(&load_creature_movement/1)
    |> Enum.each(&start/1)
  end

  defp load_creature_movement(%Mangos.Creature{} = creature) do
    creature_movement =
      Mangos.CreatureMovement.query(creature.guid)
      |> Mangos.Repo.all()

    Map.put(creature, :creature_movement, creature_movement)
  end

  defp start(%Mangos.Creature{} = creature) do
    creature
    |> Mob.build()
    |> World.start_entity()
  end
end
