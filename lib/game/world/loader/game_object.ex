defmodule ThistleTea.Game.World.Loader.GameObject do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.System.GameEvent

  def load(cell) do
    events = GameEvent.get_events()

    Mangos.GameObject.query_cell(cell, events)
    |> Mangos.Repo.all()
    |> Enum.each(&start/1)
  end

  defp start(game_object) do
    game_object
    |> GameObject.build()
    |> World.start_entity()
  end
end
