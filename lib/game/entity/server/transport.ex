defmodule ThistleTea.Game.Entity.Server.Transport do
  @moduledoc """
  Owning process for a moving game object and its route clock.
  """

  use GenServer

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Transport, as: TransportRoute
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Network
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
      tick_ms: 50,
      offset_ms: 0,
      schedule?: true
    ]
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

  @impl GenServer
  def handle_call(:transport_info, _from, %State{} = state) do
    {:reply, {:ok, snapshot(state)}, state}
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

  @impl GenServer
  def terminate(_reason, %State{entity: entity}) do
    Transports.unpublish(entity.object.guid)
    World.remove_position(entity)
    Visibility.leave_entity(entity)
    :ok
  end

  defp move(%State{} = state, now) do
    elapsed_ms = now - state.started_at + state.offset_ms
    pose = pose_at(state, elapsed_ms)
    entity = put_pose(state.entity, state.route, pose)
    World.update_position(entity)
    entity = Visibility.refresh_entity(entity)
    Transports.publish(entity, state.route, pose)
    %{state | entity: entity, last_pose: pose}
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
         pose
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
        transport_progress_in_ms: pose.progress_ms
    }

    %{entity | game_object: game_object, movement_block: movement_block, internal: %{internal | world: world}}
  end

  defp pose_world(%TransportRoute{kind: :ship}, %{map_id: map_id}, _world), do: WorldRef.open(map_id)
  defp pose_world(%TransportRoute{}, _pose, world), do: world

  defp stationary_position(%TransportRoute{kind: :ship}, _movement_block, orientation) do
    {0.0, 0.0, 0.0, orientation}
  end

  defp stationary_position(%TransportRoute{}, %MovementBlock{stationary_position: position}, _orientation), do: position

  defp schedule_tick(%State{schedule?: false} = state), do: state
  defp schedule_tick(%State{tick_ref: ref} = state) when is_reference(ref), do: state

  defp schedule_tick(%State{tick_ms: tick_ms} = state) do
    %{state | tick_ref: Process.send_after(self(), :transport_tick, tick_ms)}
  end

  defp snapshot(%State{entity: entity, route: route, last_pose: pose}) do
    %{
      guid: entity.object.guid,
      entry: entity.object.entry,
      world: entity.internal.world,
      route_kind: route.kind,
      position: pose.position,
      progress_ms: pose.progress_ms,
      period_ms: route.period_ms
    }
  end
end
