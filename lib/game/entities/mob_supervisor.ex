defmodule ThistleTea.MobSupervisor do
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
      from(c in Mangos.Creature,
        join: ct in assoc(c, :creature_template),
        left_join: cm in assoc(c, :creature_movement),
        where: c.modelid != 0,
        select: {c, ct, cm}
      )

    children =
      Mangos.Repo.all(query)
      # workaround since this wasn't working in ecto
      |> Enum.group_by(fn {%{guid: guid}, _, _} -> guid end)
      |> Enum.map(fn {_, entries} ->
        {creature, creature_template, _} = List.first(entries)

        movements =
          entries
          |> Enum.map(fn {_, _, cm} -> cm end)
          |> Enum.filter(fn cm -> cm end)
          |> Enum.sort_by(fn cm -> cm.point end)

        creature = %{
          creature
          | creature_template: creature_template,
            creature_movement: movements
        }

        %{
          id: {ThistleTea.Mob, creature.guid},
          start: {ThistleTea.Mob, :start_link, [creature]}
        }
      end)

    Logger.info("Spawned #{length(children)} mobs.")

    opts = [strategy: :one_for_one, max_restarts: 100]
    Supervisor.init(children, opts)
  end
end
