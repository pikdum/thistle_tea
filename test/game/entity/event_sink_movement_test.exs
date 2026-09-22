defmodule ThistleTea.Game.Entity.EventSinkMovementTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.MsgMoveKnockBack
  alias ThistleTea.Game.Network.Message.MsgMoveTeleport
  alias ThistleTea.Game.Network.Message.SmsgClientControlUpdate
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove
  alias ThistleTea.Game.Network.Message.SmsgMoveKnockBack
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.Spline
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  describe "emit/3 CreatureTeleported" do
    test "projects both observer sets and every owner-local position consumer" do
      world = WorldRef.instance(329, unique_low())
      other_world = WorldRef.instance(329, world.instance_id + 1)
      mob_guid = Guid.from_low_guid(:mob, 10_917, unique_low())
      old_position = {0.0, 0.0, 0.0, 0.25}
      destination = {750.0, 0.0, 0.0, 5.42797}

      observers = [
        old: {world, {0.0, 0.0, 0.0}},
        overlap: {world, {375.0, 0.0, 0.0}},
        new: {world, {750.0, 0.0, 0.0}},
        other_copy: {other_world, {750.0, 0.0, 0.0}}
      ]

      observer_state = start_observers(observers)
      missing_guid = Guid.from_low_guid(:player, unique_low())
      SpatialHash.insert(:players, missing_guid, world, 0.0, 0.0, 0.0)
      test_pid = self()

      on_exit(fn ->
        ChaseWatch.unwatch(test_pid)
        Metadata.delete(mob_guid)
        SpatialHash.remove(:mobs, mob_guid)
        SpatialHash.remove(:players, missing_guid)
        stop_observers(observer_state)
      end)

      mob =
        mob(mob_guid, world, old_position)
        |> Visibility.join_entity()

      World.update_position(mob)

      SpatialHash.put_projection(mob_guid, %Spline{
        world: world,
        origin: {0.0, 0.0, 0.0},
        nodes: [{100.0, 0.0, 0.0}],
        started_at: 0,
        duration_ms: 100_000
      })

      Metadata.put(mob_guid, %{orientation: 0.25})
      ChaseWatch.watch(mob_guid, self(), {0.0, 0.0, 0.0}, 1.0)

      old_cell = mob.internal.visibility_cell
      new_cell = Visibility.current_cell(%{mob | movement_block: stationary_block(destination, 5_000)})
      :ok = Group.monitor(Visibility.group_name(), Visibility.cell_key(old_cell))
      :ok = Group.monitor(Visibility.group_name(), Visibility.cell_key(new_cell))

      movement_block = stationary_block(destination, 5_000)

      effect = %Effects.CreatureTeleported{
        world: world,
        from_position: old_position,
        position: destination,
        movement_block: movement_block,
        script_id: 10_917,
        declared_map_id: 329,
        options: 0
      }

      updated = EventSink.emit(mob, effect)

      assert collect_observer_packets(observer_state) == %{new: 1, old: 1, other_copy: 0, overlap: 2}

      assert_receive {:target_moved, ^mob_guid}
      assert_group_events(old_cell, new_cell, mob_guid)

      assert World.position(mob_guid) == {world, 750.0, 0.0, 0.0}
      assert Position.projection(mob_guid) == nil
      assert SpatialHash.cell(world, 750.0, 0.0, 0.0) == World.cell_for(mob_guid)
      assert updated.internal.visibility_cell == new_cell
      assert Metadata.query(mob_guid, [:orientation]) == %{orientation: 5.42797}

      Group.demonitor(Visibility.group_name(), Visibility.cell_key(old_cell))
      Group.demonitor(Visibility.group_name(), Visibility.cell_key(new_cell))
      ChaseWatch.unwatch(self())
      Metadata.delete(mob_guid)
      World.remove_position(updated)
      Visibility.leave_entity(updated)
      stop_observers(observer_state)
    end

    test "retains and publishes a later same-batch spline from the destination" do
      world = WorldRef.instance(329, unique_low())
      guid = Guid.from_low_guid(:mob, 10_435, unique_low())
      destination = {100.0, 200.0, 300.0, 1.0}
      stationary = stationary_block(destination, 1_000)

      on_exit(fn ->
        SpatialHash.remove(:mobs, guid)
        Metadata.delete(guid)
      end)

      entity =
        mob(guid, world, {0.0, 0.0, 0.0, 0.0})
        |> Visibility.join_entity()

      World.update_position(entity)

      movement_block = %{
        stationary
        | movement_flags: 0x00400001,
          spline_nodes: [{110.0, 200.0, 300.0}],
          spline_flags: 0x100,
          spline_id: 9,
          spline_start_position: {100.0, 200.0, 300.0},
          duration: 1_000
      }

      entity = %{
        entity
        | movement_block: movement_block,
          internal: %{
            entity.internal
            | movement_start_time: 1_000,
              movement_start_position: {100.0, 200.0, 300.0}
          }
      }

      teleport = %Effects.CreatureTeleported{
        world: world,
        from_position: {0.0, 0.0, 0.0, 0.0},
        position: destination,
        movement_block: stationary,
        script_id: 1_043_504,
        declared_map_id: 0,
        options: 0
      }

      updated = EventSink.emit(entity, [teleport, Effects.monster_move()])

      assert updated.movement_block == movement_block

      assert %Spline{} = projection = Position.projection(guid)
      assert projection.world == world
      assert projection.origin == {100.0, 200.0, 300.0}
      assert projection.nodes == [{110.0, 200.0, 300.0}]
      assert projection.started_at == 1_000

      World.remove_position(updated)
      Visibility.leave_entity(updated)
      Metadata.delete(guid)
    end
  end

  describe "emit/3" do
    test "player control uses its explicit owner and movement reaches owner and observers" do
      world = WorldRef.instance(0, unique_low())
      guid = Guid.from_low_guid(:player, unique_low())
      observers = start_observers(owner: {world, {0.0, 0.0, 0.0}}, nearby: {world, {1.0, 0.0, 0.0}})
      [{:owner, _owner_guid, owner_pid} | _] = observers
      {:ok, _} = Entity.register(guid)

      character = %Character{
        object: %Object{guid: guid},
        unit: %Unit{health: 100},
        movement_block: stationary_block({0.0, 0.0, 0.0, 0.0}, 0),
        internal: %Internal{world: world, spline_id: 1}
      }

      on_exit(fn ->
        World.remove_position(character)
        Metadata.delete(guid)
        stop_observers(observers)
      end)

      EventSink.emit(character, Effects.client_control_changed(false), Context.new(owner_pid))

      assert_receive {:observer, :owner,
                      {:"$gen_cast", {:send_packet, %SmsgClientControlUpdate{guid: ^guid, allow_movement?: false}}}}

      refute_received {:"$gen_cast", {:send_packet, %SmsgClientControlUpdate{}}}

      impulse = %Effects.Knockback{cos_angle: 0.0, sin_angle: 1.0, horizontal_speed: 12.0, vertical_speed: 7.0}
      EventSink.emit(character, impulse, Context.new(owner_pid))

      assert_receive {:observer, :owner,
                      {:"$gen_cast", {:send_packet, %SmsgMoveKnockBack{guid: ^guid, vertical_speed: -7.0}}}}

      refute_received {:observer, :nearby, {:"$gen_cast", {:send_packet, %SmsgMoveKnockBack{}, _}}}

      character = %{
        character
        | movement_block: %{character.movement_block | spline_nodes: [{7.0, 0.0, 0.0}], duration: 1_000}
      }

      EventSink.emit(character, Effects.monster_move(), Context.new(owner_pid))
      assert_receive {:"$gen_cast", {:send_packet, %SmsgMonsterMove{guid: ^guid, move_type: 0}}}

      assert_receive {:observer, :nearby,
                      {:"$gen_cast", {:send_packet, %SmsgMonsterMove{guid: ^guid, move_type: 0}, _}}}

      EventSink.emit(character, Effects.movement_stopped(), Context.new(owner_pid))
      assert_receive {:"$gen_cast", {:send_packet, %SmsgMonsterMove{guid: ^guid, move_type: 1}}}

      assert_receive {:observer, :nearby,
                      {:"$gen_cast", {:send_packet, %SmsgMonsterMove{guid: ^guid, move_type: 1}, _}}}
    end

    test "possessed mob control is delivered to its controller" do
      owner = Guid.from_low_guid(:player, unique_low())
      {:ok, _} = Entity.register(owner)
      mob = mob(Guid.from_low_guid(:mob, 1, unique_low()), WorldRef.open(0), {0.0, 0.0, 0.0, 0.0})
      mob = %{mob | internal: %{mob.internal | pet: %Pet{possessed?: true, owner_guid: owner}}}
      guid = mob.object.guid
      EventSink.emit(mob, Effects.client_control_changed(false))
      assert_receive {:"$gen_cast", {:send_packet, %SmsgClientControlUpdate{guid: ^guid, allow_movement?: false}, _}}

      impulse = %Effects.Knockback{cos_angle: 1.0, sin_angle: 0.0, horizontal_speed: 10.0, vertical_speed: 10.0}
      EventSink.emit(mob, impulse)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgMoveKnockBack{guid: ^guid, vertical_speed: -10.0}, _}}
    end
  end

  describe "handle_info/2 controlled movement" do
    test "acknowledged possession launches reach observers once and never relaunch the controller" do
      world = WorldRef.instance(0, unique_low())
      observers = start_observers(owner: {world, {0.0, 0.0, 0.0}}, nearby: {world, {1.0, 0.0, 0.0}})
      [{:owner, owner_guid, _} | _] = observers
      guid = Guid.from_low_guid(:mob, 1, unique_low())
      entity = mob(guid, world, {0.0, 0.0, 0.0, 0.0})
      entity = put_in(entity.internal.pet, %Pet{owner_guid: owner_guid, possessed?: true})
      entity = Visibility.join_entity(entity)

      on_exit(fn ->
        World.remove_position(entity)
        Metadata.delete(guid)
        stop_observers(observers)
      end)

      movement = %{
        entity.movement_block
        | position: {2.0, 0.0, 1.0, 0.0},
          movement_flags: 0x2000,
          cos_angle: 1.0,
          sin_angle: 0.0,
          xy_speed: 10.0,
          z_speed: -10.0
      }

      payload = MovementBlock.movement_info_to_binary(movement)
      assert {:noreply, moved} = MobServer.handle_info({:controlled_move, payload, 0xF1}, entity)
      assert moved.movement_block.position == movement.position
      assert World.position(guid) == {world, 2.0, 0.0, 1.0}
      assert_receive {:observer, :nearby, {:"$gen_cast", {:send_packet, %MsgMoveKnockBack{guid: ^guid}, _}}}
      refute_receive {:observer, :owner, {:"$gen_cast", {:send_packet, %MsgMoveKnockBack{}, _}}}

      dead = put_in(entity.unit.health, 0)
      assert MobServer.handle_info({:controlled_move, payload, 0xF1}, dead) == {:noreply, dead}
      released = put_in(entity.internal.pet, nil)
      assert MobServer.handle_info({:controlled_move, payload, 0xF1}, released) == {:noreply, released}
      Visibility.leave_entity(moved)
    end
  end

  defp mob(guid, world, position) do
    %Mob{
      object: %Object{guid: guid, entry: 10_917},
      unit: %Unit{health: 100, flags: 0, auras: []},
      movement_block: stationary_block(position, 0),
      internal: %Internal{world: world}
    }
  end

  defp stationary_block(position, timestamp) do
    %MovementBlock{
      movement_flags: 0,
      timestamp: timestamp,
      position: position,
      fall_time: 0,
      spline_nodes: [],
      spline_flags: 0,
      duration: 0,
      time_passed: 0
    }
  end

  defp start_observers(observers) do
    Enum.map(observers, fn {label, {world, {x, y, z}}} ->
      guid = Guid.from_low_guid(:player, unique_low())
      pid = start_observer(label, guid)
      SpatialHash.insert(:players, guid, world, x, y, z)
      {label, guid, pid}
    end)
  end

  defp start_observer(label, guid) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _owner} = Entity.register(guid)
        send(parent, {:observer_ready, self()})
        observer_loop(parent, label, guid)
      end)

    assert_receive {:observer_ready, ^pid}
    pid
  end

  defp observer_loop(parent, label, guid) do
    receive do
      :stop ->
        Entity.unregister(guid)

      {:flush, sender} ->
        send(sender, {:observer_flushed, label})
        observer_loop(parent, label, guid)

      message ->
        send(parent, {:observer, label, message})
        observer_loop(parent, label, guid)
    end
  end

  defp stop_observers(observer_state) do
    Enum.each(observer_state, fn {_label, guid, pid} ->
      SpatialHash.remove(:players, guid)
      send(pid, :stop)
    end)
  end

  defp collect_observer_packets(observer_state) do
    Enum.each(observer_state, fn {_label, _guid, pid} -> send(pid, {:flush, self()}) end)
    collect_observer_packets(MapSet.new(), length(observer_state), %{})
  end

  defp collect_observer_packets(flushed, expected, counts) do
    if MapSet.size(flushed) == expected do
      counts
    else
      receive do
        {:observer, label, {:"$gen_cast", {:send_packet, %MsgMoveTeleport{}, [source_guid: _source_guid]}}} ->
          collect_observer_packets(flushed, expected, Map.update(counts, label, 1, &(&1 + 1)))

        {:observer_flushed, label} ->
          collect_observer_packets(MapSet.put(flushed, label), expected, Map.put_new(counts, label, 0))
      end
    end
  end

  defp assert_group_events(old_cell, new_cell, guid) do
    wanted = MapSet.new([{:left, Visibility.cell_key(old_cell)}, {:joined, Visibility.cell_key(new_cell)}])
    collect_group_events(wanted, guid)
  end

  defp collect_group_events(wanted, guid) do
    if MapSet.size(wanted) == 0 do
      :ok
    else
      receive do
        {:group, events, %{name: group}} ->
          assert group == Visibility.group_name()

          found =
            events
            |> Enum.filter(&match?(%Group.Event{meta: %{guid: ^guid}}, &1))
            |> Enum.map(&{&1.type, &1.key})

          collect_group_events(MapSet.difference(wanted, MapSet.new(found)), guid)
      end
    end
  end

  defp unique_low do
    rem(System.unique_integer([:positive, :monotonic]), 0x00FFFFFF)
  end
end
