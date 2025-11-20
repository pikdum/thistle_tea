defmodule ThistleTea.Game.World.Loader.Mob do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.World.EntitySupervisor

  def load(cell) do
    Mangos.Creature.query_cell(cell)
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
    mob_data = Mob.build(creature)
    DynamicSupervisor.start_child(EntitySupervisor, {MobServer, mob_data})
  end
end
