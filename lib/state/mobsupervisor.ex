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
        join: ct in CreatureTemplate,
        on: ct.entry == c.id,
        select: {c, ct}
      )

    children =
      Mangos.all(query)
      |> Enum.map(fn {creature, creature_template} ->
        %{
          id: {ThistleTea.Mob, creature.guid},
          start: {ThistleTea.Mob, :start_link, [creature, creature_template]}
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
