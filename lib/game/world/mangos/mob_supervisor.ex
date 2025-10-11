defmodule ThistleTea.Game.World.Mangos.MobSupervisor do
  use Supervisor

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Mob
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
    Mangos.Creature.query_cell(cell)
    |> Mangos.Repo.all()
    |> Enum.map(&spec/1)
  end

  defp spec(%Mangos.Creature{} = creature) do
    mob_data = Mob.Data.build(creature)

    %{
      id: {Mob.Server, mob_data.object.guid},
      start: {Mob.Server, :start_link, [mob_data]}
    }
  end
end
