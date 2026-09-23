defmodule ThistleTea.Game.Entity.Server.Corpse do
  @moduledoc """
  Owning GenServer for a corpse entity; registers it in the world and serves
  update-object requests from observers.
  """
  use GenServer

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  def start_link(%Corpse{} = state) do
    GenServer.start_link(__MODULE__, state, name: EntityRegistry.via(state.object.guid))
  end

  @impl GenServer
  def init(%Corpse{} = state) do
    Process.flag(:trap_exit, true)

    metadata =
      state.corpse.owner
      |> Metadata.get()
      |> Kernel.||(%{})
      |> Map.take([:faction_template, :faction_template_id, :faction_can_have_reputation?])

    Metadata.put(
      state.object.guid,
      Map.merge(metadata, %{
        owner: state.corpse.owner,
        ghost_time: state.internal.corpse_reclaim.released_at
      })
    )

    World.update_position(state)
    state = Visibility.join_entity(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    Core.update_object(state)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    World.remove_position(state)
    Visibility.leave_entity(state)
    Metadata.delete(state.object.guid)
  end
end
