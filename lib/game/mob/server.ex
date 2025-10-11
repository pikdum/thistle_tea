defmodule ThistleTea.Game.Mob.Server do
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Message.SmsgMonsterMove
  alias ThistleTea.Game.Mob
  alias ThistleTea.Util

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
    {x0, y0, z0, o} = state.movement_block.position
    map = state.internal.map
    guid = state.object.guid

    nearby_players = SpatialHash.query(:players, map, x0, y0, z0, 250)
    path = ThistleTea.Pathfinding.find_path(map, {x0, y0, z0}, {x, y, z})

    duration =
      Util.calculate_total_duration([{x0, y0, z0} | path], state.movement_block.run_speed * 7.0) |> trunc() |> max(1)

    {xd, yd, zd} = List.last(path)

    move = %SmsgMonsterMove{
      guid: guid,
      spline_point: {x0, y0, z0},
      spline_id: 0,
      move_type: 0,
      spline_flags: 0x100,
      duration: duration,
      splines: path
    }

    payload = SmsgMonsterMove.to_binary(move)

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
