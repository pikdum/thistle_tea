defmodule ThistleTea.Game.Mob.Server do
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Message.SmsgMonsterMove
  alias ThistleTea.Game.Mob

  @smsg_monster_move 0x0DD

  def start_link(%Mob.Data{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%Mob.Data{} = state) do
    Process.flag(:trap_exit, true)
    Entity.Core.set_position(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = Entity.Core.update_packet(state)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = Entity.Movement.start_move_to(state, {x, y, z})
    payload = SmsgMonsterMove.build(state) |> SmsgMonsterMove.to_binary()

    {_, _, _, o} = state.movement_block.position
    {xd, yd, zd} = List.last(state.movement_block.spline_nodes)

    nearby_players = Entity.Core.nearby_players(state)

    # TODO: i should come up with a packet struct that takes opcode as atom, payload as binary
    # and then use that as the interface instead of raw binaries
    for {_guid, pid, _distance} <- nearby_players do
      GenServer.cast(pid, {:send_packet, @smsg_monster_move, payload})
    end

    {:noreply, %{state | movement_block: %{state.movement_block | position: {xd, yd, zd, o}}}}
  end

  @impl GenServer
  def handle_call(:get_entity, _from, state), do: {:reply, :mob, state}

  @impl GenServer
  def handle_call(:get_name, _from, state), do: {:reply, state.internal.name, state}

  @impl GenServer
  def terminate(_reason, state), do: Entity.Core.remove_position(state)
end
