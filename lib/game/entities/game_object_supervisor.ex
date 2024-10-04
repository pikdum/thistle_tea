defmodule ThistleTea.GameObjectSupervisor do
  use Supervisor
  import Ecto.Query
  alias ThistleTea.Mangos
  require Logger

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    query =
      from(g in GameObject,
        join: gt in assoc(g, :game_object_template),
        preload: [game_object_template: gt],
        select: g
      )

    children =
      Mangos.all(query)
      |> Enum.map(fn game_object ->
        %{
          id: {ThistleTea.GameObject, game_object.guid},
          start: {ThistleTea.GameObject, :start_link, [game_object]}
        }
      end)

    Logger.info("Spawned #{length(children)} game objects.")

    opts = [strategy: :one_for_one, max_restarts: 100]
    Supervisor.init(children, opts)
  end
end
