defmodule ThistleTea.Game.Entity.Server.Transport do
  @moduledoc """
  Owning process for a moving game object and its route clock.
  """

  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Transport, as: TransportRoute
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  @tick_ms 50

  defmodule State do
    @moduledoc false

    defstruct [
      :entity,
      :route,
      :started_at,
      :last_pose,
      :tick_ref,
      :clock,
      passengers: %{},
      tick_ms: 50,
      offset_ms: 0,
      schedule?: true
    ]
  end

  defmodule Passenger do
    @moduledoc false

    defstruct [:pid, :monitor]
  end

  def start_link({%GameObject{} = entity, %TransportRoute{} = route}) do
    start_link({entity, route, []})
  end

  def start_link({%GameObject{} = entity, %TransportRoute{} = route, opts}) when is_list(opts) do
    GenServer.start_link(__MODULE__, {entity, route, opts}, name: EntityRegistry.via(entity.object.guid))
  end

  @impl GenServer
  def init({%GameObject{} = entity, %TransportRoute{} = route, opts}) do
    clock = Keyword.get(opts, :clock, &Time.now/0)
    now = clock.()

    state = %State{
      entity: entity,
      route: route,
      started_at: now,
      clock: clock,
      tick_ms: Keyword.get(opts, :tick_ms, @tick_ms),
      schedule?: Keyword.get(opts, :schedule, true)
    }

    {:ok, state |> move(now) |> schedule_tick()}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, %State{entity: entity} = state) do
    entity
    |> Core.update_object()
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  def handle_cast({:transport_leave, player_guid}, %State{} = state) do
    {:noreply, state |> remove_passenger(player_guid) |> publish()}
  end

  @impl GenServer
  def handle_call(:transport_info, _from, %State{} = state) do
    {:reply, {:ok, snapshot(state)}, state}
  end

  def handle_call(:transport_update, _from, %State{entity: entity} = state) do
    {:reply, {:ok, Core.update_object(entity)}, state}
  end

  def handle_call(
        {:transport_board, player_guid, world, local_position},
        {player_pid, _tag},
        %State{entity: %{internal: %{world: world}}} = state
      ) do
    if Entity.pid(player_guid) == player_pid and TransportLogic.valid_passenger_position?(local_position) do
      state = state |> put_passenger(player_guid, player_pid) |> publish()
      {:reply, {:ok, snapshot(state)}, state}
    else
      {:reply, {:error, :invalid_passenger}, state}
    end
  end

  def handle_call({:transport_board, _player_guid, _world, _local_position}, _from, %State{} = state) do
    {:reply, {:error, :wrong_world}, state}
  end

  def handle_call({:advance, milliseconds}, _from, %State{} = state) when is_integer(milliseconds) do
    state = %{state | offset_ms: state.offset_ms + milliseconds}
    state = move(state, state.clock.())
    {:reply, {:ok, snapshot(state)}, state}
  end

  @impl GenServer
  def handle_info(:transport_tick, %State{} = state) do
    state = %{state | tick_ref: nil}
    {:noreply, state |> move(state.clock.()) |> schedule_tick()}
  rescue
    _error ->
      {:noreply, schedule_tick(%{state | tick_ref: nil})}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %State{} = state) do
    passengers =
      Map.reject(state.passengers, fn {_guid, %Passenger{monitor: passenger_monitor}} ->
        passenger_monitor == monitor
      end)

    {:noreply, %{state | passengers: passengers} |> publish()}
  end

  @impl GenServer
  def terminate(_reason, %State{entity: entity, route: route, passengers: passengers}) do
    Enum.each(passengers, fn {_guid, %Passenger{pid: pid}} ->
      send(pid, {:transport_lost, entity.object.guid})
    end)

    remove_from_world_players(entity, route)
    Transports.unpublish(entity.object.guid)
    World.remove_position(entity)
    Visibility.leave_entity(entity)
    :ok
  end

  defp move(%State{} = state, now) do
    elapsed_ms = now - state.started_at + state.offset_ms
    pose = pose_at(state, elapsed_ms)
    entity = put_pose(state.entity, state.route, pose, elapsed_ms)
    World.update_position(entity)
    next_state = %{state | entity: entity, last_pose: pose}
    publish(next_state)
    entity = Visibility.refresh_entity(entity)
    next_state = %{next_state | entity: entity}
    sync_world_visibility(state, next_state)
    notify_passengers(state, next_state)
    next_state
  end

  defp pose_at(%State{route: %TransportRoute{kind: :ship} = route}, elapsed_ms) do
    TransportLogic.pose_at(route, elapsed_ms)
  end

  defp pose_at(
         %State{
           entity: %GameObject{
             movement_block: %MovementBlock{stationary_position: stationary_position},
             game_object: game_object
           },
           route: %TransportRoute{kind: :animation} = route
         },
         elapsed_ms
       ) do
    rotation = {game_object.rotation0, game_object.rotation1, game_object.rotation2, game_object.rotation3}
    TransportLogic.pose_at(route, elapsed_ms, stationary_position, rotation)
  end

  defp put_pose(
         %GameObject{game_object: game_object, movement_block: movement_block, internal: %Internal{} = internal} =
           entity,
         %TransportRoute{} = route,
         pose,
         elapsed_ms
       ) do
    {x, y, z, orientation} = pose.position
    world = pose_world(route, pose, internal.world)

    game_object = %{
      game_object
      | pos_x: x,
        pos_y: y,
        pos_z: z,
        facing: orientation,
        rotation2: :math.sin(orientation / 2),
        rotation3: :math.cos(orientation / 2)
    }

    movement_block = %{
      movement_block
      | position: pose.position,
        stationary_position: stationary_position(route, movement_block, orientation),
        transport_progress_in_ms: transport_progress(route, pose, elapsed_ms)
    }

    %{entity | game_object: game_object, movement_block: movement_block, internal: %{internal | world: world}}
  end

  defp pose_world(%TransportRoute{kind: :ship}, %{map_id: map_id}, _world), do: WorldRef.open(map_id)
  defp pose_world(%TransportRoute{}, _pose, world), do: world

  defp stationary_position(%TransportRoute{kind: :ship}, _movement_block, orientation) do
    {0.0, 0.0, 0.0, orientation}
  end

  defp stationary_position(%TransportRoute{}, %MovementBlock{stationary_position: position}, _orientation), do: position

  defp transport_progress(%TransportRoute{kind: :ship}, _pose, elapsed_ms) do
    Integer.mod(elapsed_ms, 0x1_0000_0000)
  end

  defp transport_progress(%TransportRoute{}, pose, _elapsed_ms), do: pose.progress_ms

  defp schedule_tick(%State{schedule?: false} = state), do: state
  defp schedule_tick(%State{tick_ref: ref} = state) when is_reference(ref), do: state

  defp schedule_tick(%State{tick_ms: tick_ms} = state) do
    %{state | tick_ref: Process.send_after(self(), :transport_tick, tick_ms)}
  end

  defp put_passenger(%State{} = state, player_guid, player_pid) do
    case Map.get(state.passengers, player_guid) do
      %Passenger{pid: ^player_pid} ->
        state

      %Passenger{monitor: monitor} ->
        Process.demonitor(monitor, [:flush])
        passenger = %Passenger{pid: player_pid, monitor: Process.monitor(player_pid)}
        %{state | passengers: Map.put(state.passengers, player_guid, passenger)}

      nil ->
        passenger = %Passenger{pid: player_pid, monitor: Process.monitor(player_pid)}
        %{state | passengers: Map.put(state.passengers, player_guid, passenger)}
    end
  end

  defp remove_passenger(%State{} = state, player_guid) do
    case Map.pop(state.passengers, player_guid) do
      {%Passenger{monitor: monitor}, passengers} ->
        Process.demonitor(monitor, [:flush])
        %{state | passengers: passengers}

      {nil, _passengers} ->
        state
    end
  end

  defp publish(%State{entity: entity, route: route, last_pose: pose, passengers: passengers} = state) do
    Transports.publish(entity, route, pose, map_size(passengers))
    state
  end

  defp sync_world_visibility(
         %State{entity: %{internal: %{world: previous_world}}},
         %State{entity: %{internal: %{world: current_world}}} = state
       )
       when previous_world != current_world do
    passenger_guids = Map.keys(state.passengers)
    remove_from_world_players(state.entity.object.guid, previous_world, passenger_guids)
    create_for_world_players(state.entity, current_world, passenger_guids)
    :ok
  end

  defp sync_world_visibility(%State{}, %State{}), do: :ok

  defp remove_from_world_players(%GameObject{} = entity, %TransportRoute{kind: :ship}) do
    remove_from_world_players(entity.object.guid, entity.internal.world, [])
  end

  defp remove_from_world_players(%GameObject{}, %TransportRoute{}), do: :ok

  defp remove_from_world_players(guid, world, excluded_guids) do
    packet = UpdateObject.out_of_range([guid])

    world
    |> player_guids()
    |> Enum.reject(&(&1 in excluded_guids))
    |> Enum.each(&Network.send_packet(packet, &1))
  end

  defp create_for_world_players(%GameObject{} = entity, world, excluded_guids) do
    update = %{Core.update_object(entity) | has_transport: false}

    world
    |> player_guids()
    |> Enum.reject(&(&1 in excluded_guids))
    |> Enum.each(&Network.send_packet(update, &1))
  end

  defp player_guids(world) do
    world
    |> World.guids()
    |> Enum.filter(&(Guid.entity_type(&1) == :player))
  end

  defp notify_passengers(%State{last_pose: nil}, %State{}), do: :ok

  defp notify_passengers(%State{} = previous, %State{} = current) do
    if pose_changed?(previous, current) do
      transport = snapshot(current)

      Enum.each(current.passengers, fn {_guid, %Passenger{pid: pid}} ->
        send(pid, {:transport_pose, transport})
      end)
    end
  end

  defp pose_changed?(%State{entity: previous_entity, last_pose: previous}, %State{
         entity: current_entity,
         last_pose: current
       }) do
    previous.position != current.position or
      previous.map_id != current.map_id or
      previous_entity.internal.world != current_entity.internal.world
  end

  defp snapshot(%State{entity: entity, route: route, last_pose: pose, passengers: passengers}) do
    %{
      guid: entity.object.guid,
      entry: entity.object.entry,
      world: entity.internal.world,
      name: route.name,
      route_kind: route.kind,
      position: pose.position,
      progress_ms: pose.progress_ms,
      period_ms: route.period_ms,
      frame_index: pose.frame_index,
      moving?: pose.moving?,
      passenger_count: map_size(passengers)
    }
  end
end
