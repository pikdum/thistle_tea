defmodule ThistleTea.GameObjectSupervisor do
  use Supervisor
  import Ecto.Query
  alias ThistleTea.DB.Mangos
  require Logger

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    query =
      from(g in Mangos.GameObject,
        join: gt in assoc(g, :game_object_template),
        preload: [game_object_template: gt],
        select: g
      )

    children =
      Mangos.Repo.all(query)
      |> Enum.map(fn game_object ->
        game_object = ThistleTea.Game.GameObject.Data.build(game_object)

        %{
          id: {ThistleTea.Game.GameObject.Server, game_object.object.guid},
          start: {ThistleTea.Game.GameObject.Server, :start_link, [game_object]}
        }
      end)

    Logger.info("Spawned #{length(children)} game objects.")

    opts = [strategy: :one_for_one, max_restarts: 100]
    Supervisor.init(children, opts)
  end
end
