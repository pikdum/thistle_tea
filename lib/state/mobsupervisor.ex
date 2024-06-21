defmodule ThistleTea.MobSupervisor do
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
      from(c in Creature,
        join: ct in assoc(c, :creature_template),
        left_join: cm in assoc(c, :creature_movement),
        preload: [creature_template: ct, creature_movement: cm],
        where: c.modelid != 0,
        select: c
      )

    children =
      Mangos.all(query)
      |> Enum.map(fn creature ->
        %{
          id: {ThistleTea.Mob, creature.guid},
          start: {ThistleTea.Mob, :start_link, [creature]}
        }
      end)

    Logger.info("Spawned #{length(children)} mobs.")

    Supervisor.init(children, strategy: :one_for_one)
  end
end
