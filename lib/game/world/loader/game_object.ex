defmodule ThistleTea.Game.World.Loader.GameObject do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Server.GameObject, as: GameObjectServer
  alias ThistleTea.Game.World.EntitySupervisor

  def load(cell) do
    Mangos.GameObject.query_cell(cell)
    |> Mangos.Repo.all()
    |> Enum.each(&start/1)
  end

  defp start(game_object) do
    game_object_data = GameObject.build(game_object)
    DynamicSupervisor.start_child(EntitySupervisor, {GameObjectServer, game_object_data})
  end
end
