defmodule ThistleTea.Game.World.Mangos.GameObjectSupervisor do
  use Supervisor

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.GameObject
  alias ThistleTea.Game.World.CellRegistry

  require Logger

  def start_link(cell) do
    Supervisor.start_link(__MODULE__, cell, name: via_tuple(cell))
  end

  defp via_tuple(cell) do
    {:via, Registry, {CellRegistry, {__MODULE__, cell}}}
  end

  @impl Supervisor
  def init(cell) do
    children = children(cell)
    opts = [strategy: :one_for_one, max_restarts: 100]
    Supervisor.init(children, opts)
  end

  defp children(cell) do
    Mangos.GameObject.query_cell(cell)
    |> Mangos.Repo.all()
    |> Enum.map(&spec/1)
  end

  defp spec(game_object) do
    game_object = GameObject.Data.build(game_object)

    %{
      id: {GameObject.Server, game_object.object.guid},
      start: {GameObject.Server, :start_link, [game_object]}
    }
  end
end
