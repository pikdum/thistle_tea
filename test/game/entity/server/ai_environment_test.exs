defmodule ThistleTea.Game.Entity.Server.AIEnvironmentTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.InstanceData.Snapshot
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.ScriptedEvent
  alias ThistleTea.Game.World.System.ScriptedEvent.Event
  alias ThistleTea.Game.WorldRef
  alias ThistleTea.Native.Namigator

  describe "context/3" do
    test "captures an immutable observation of an explicit actor" do
      actor_guid = Guid.from_low_guid(:player, 98_001)
      world = %WorldRef{map_id: 0}

      SpatialHash.update(:players, actor_guid, world, 100.0, 0.0, 0.0)
      Metadata.put(actor_guid, %{alive?: true, level: 10})

      on_exit(fn ->
        SpatialHash.remove(:players, actor_guid)
        Metadata.delete(actor_guid)
      end)

      perception = AIEnvironment.context(mob(world), 1_000, Request.actor(actor_guid)).perception

      SpatialHash.update(:players, actor_guid, world, 200.0, 0.0, 0.0)
      Metadata.update(actor_guid, %{alive?: false, level: 20})

      assert Perception.position(perception, actor_guid) == {world, 100.0, 0.0, 0.0}
      assert Perception.distance(perception, actor_guid) == 100.0
      assert Perception.metadata(perception, actor_guid) == %{alive?: true, level: 10}
      assert Perception.nearby(perception, :players, 200.0) == []
    end

    test "expands the snapshot for behavior-declared observation ranges" do
      actor_guid = Guid.from_low_guid(:player, 98_003)
      world = %WorldRef{map_id: 0}
      event = %AIEvent{event_type: :friendly_hp, param2: 150}
      mob = mob(world)
      mob = %{mob | internal: %{mob.internal | creature: %Creature{ai_events: [event]}}}

      SpatialHash.update(:players, actor_guid, world, 100.0, 0.0, 0.0)
      Metadata.put(actor_guid, %{alive?: true})

      on_exit(fn ->
        SpatialHash.remove(:players, actor_guid)
        Metadata.delete(actor_guid)
      end)

      perception = AIEnvironment.context(mob, 1_000).perception

      assert Perception.nearby(perception, :players, 150.0) == [{actor_guid, 100.0}]
    end

    test "checks line of sight only for combat-relevant actors" do
      world = %WorldRef{map_id: 999}
      target_guid = Guid.from_low_guid(:player, 98_004)
      nearby_guids = Enum.map(1..20, &Guid.from_low_guid(:mob, 1, 98_004 + &1))

      put_actor(:players, target_guid, world, 10.0)

      Enum.with_index(nearby_guids, 1)
      |> Enum.each(fn {guid, offset} -> put_actor(:mobs, guid, world, offset / 100) end)

      on_exit(fn ->
        remove_actor(:players, target_guid)
        Enum.each(nearby_guids, &remove_actor(:mobs, &1))
      end)

      tracer = start_line_of_sight_trace()

      mob = mob(world)
      mob = %{mob | unit: %{mob.unit | target: target_guid}, internal: %{mob.internal | in_combat: true}}
      perception = AIEnvironment.context(mob, 1_000).perception

      assert length(Perception.nearby(perception, :mobs, 2.0)) == 20
      assert line_of_sight_call_count(tracer) == 1
    end

    test "bounds a regular combat snapshot to nearby movement coordination" do
      world = %WorldRef{map_id: 999}
      actor_guid = Guid.from_low_guid(:mob, 1, 98_025)

      put_actor(:mobs, actor_guid, world, 3.0)
      on_exit(fn -> remove_actor(:mobs, actor_guid) end)

      mob = mob(world)
      mob = %{mob | internal: %{mob.internal | in_combat: true}}
      perception = AIEnvironment.context(mob, 1_000).perception

      assert Perception.nearby(perception, :mobs, 75.0) == []
    end

    test "observes an auto shot target after melee attack stop clears the selected target" do
      world = %WorldRef{map_id: 0}
      player_guid = Guid.from_low_guid(:player, 98_026)
      target_guid = Guid.from_low_guid(:mob, 1, 98_027)

      put_actor(:mobs, target_guid, world, 20.0)
      on_exit(fn -> remove_actor(:mobs, target_guid) end)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{target: 0},
        internal: %Internal{
          world: world,
          auto_shot: %{target_guid: target_guid}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      perception = AIEnvironment.context(character, 1_000).perception

      assert Perception.distance(perception, target_guid) == 20.0
      assert Perception.metadata(perception, target_guid) == %{alive?: true, level: 10}
    end

    test "captures requested script condition results" do
      world = %WorldRef{map_id: 0}
      target_guid = Guid.from_low_guid(:player, 98_028)
      game_object_guid = Guid.from_low_guid(:game_object, 21_145, 98_029)
      condition = %Condition{entry: 1, type: :nearby_game_object, value1: 21_145, value2: 30}

      SpatialHash.update(:players, target_guid, world, 0.0, 0.0, 0.0)
      SpatialHash.update(:game_objects, game_object_guid, world, 5.0, 0.0, 0.0)

      on_exit(fn ->
        SpatialHash.remove(:players, target_guid)
        SpatialHash.remove(:game_objects, game_object_guid)
      end)

      request = Request.new([target_guid], 0.0, script_conditions: [condition])
      context = AIEnvironment.context(mob(world), 1_000, request)

      assert context.script_conditions == %{1 => :met}
    end

    test "captures EventAI world facts against the current victim" do
      world = %WorldRef{map_id: 0}
      victim_guid = Guid.from_low_guid(:player, 98_030)
      game_object_guid = Guid.from_low_guid(:game_object, 21_145, 98_031)
      condition = %Condition{entry: 3, type: :nearby_game_object, value1: 21_145, value2: 10}
      event = %AIEvent{event_type: :timer_in_combat, condition: condition}

      SpatialHash.update(:players, victim_guid, world, 100.0, 0.0, 0.0)
      SpatialHash.update(:game_objects, game_object_guid, world, 105.0, 0.0, 0.0)

      on_exit(fn ->
        SpatialHash.remove(:players, victim_guid)
        SpatialHash.remove(:game_objects, game_object_guid)
      end)

      mob = mob(world)

      mob = %{
        mob
        | unit: %{mob.unit | target: victim_guid},
          internal: %{mob.internal | creature: %Creature{ai_events: [event]}}
      }

      context = AIEnvironment.context(mob, 1_000)

      assert context.script_conditions == %{3 => :met}
      assert context.script_conditions_by_target == %{victim_guid => %{3 => :met}}
    end

    test "requests scripted map-event facts from their owner" do
      world = %WorldRef{map_id: 0}
      condition = %Condition{entry: 2, type: :map_event_active, value1: 5_713}
      key = {world, 5_713}
      event = %Event{id: 5_713, world: world}

      previous = :sys.get_state(ScriptedEvent)
      :sys.replace_state(ScriptedEvent, &Map.put(&1, key, event))
      on_exit(fn -> :sys.replace_state(ScriptedEvent, fn _state -> previous end) end)

      request = Request.new([], 0.0, script_conditions: [condition])
      context = AIEnvironment.context(mob(world), 1_000, request)

      assert context.script_conditions == %{2 => :met}
    end

    test "batches EventAI and loaded-script instance fields once for the exact copy" do
      owner = self()
      world = WorldRef.instance(329, 51)
      event_condition = %Condition{entry: 3_756, type: :instance_data, value1: 7, value2: 1}
      script_condition = %Condition{entry: 3_758, type: :instance_data, value1: 5, value2: 3}
      event = %AIEvent{event_type: :timer_in_combat, condition: event_condition}
      mob = mob(world)
      mob = %{mob | internal: %{mob.internal | creature: %Creature{ai_events: [event]}}}
      request = Request.new([], 0.0, script_conditions: [script_condition, event_condition])

      context =
        AIEnvironment.context(mob, 1_000, request,
          instance_data: fn passed_world, fields ->
            send(owner, {:instance_data, passed_world, MapSet.new(fields)})

            %Snapshot{
              world: passed_world,
              status: :available,
              script_name: "instance_stratholme",
              fields: %{7 => {:ok, 1}, 5 => {:error, {:unsupported_field, 5}}}
            }
          end
        )

      assert context.instance_data.world == world
      assert_received {:instance_data, ^world, fields}
      assert fields == MapSet.new([5, 7])
      refute_received {:instance_data, _, _}
    end

    test "skips instance lookup when no condition requests it" do
      AIEnvironment.context(mob(WorldRef.open(0)), 1_000, %Request{},
        instance_data: fn _world, _fields -> flunk("instance lookup was not planned") end
      )
    end

    test "uses a game object's full instance identity" do
      owner = self()
      world = WorldRef.instance(329, 52)
      condition = %Condition{type: :instance_data, value1: 7, value2: 0}
      request = Request.new([], 0.0, script_conditions: [condition])

      context =
        AIEnvironment.context(game_object(world), 1_000, request,
          instance_data: fn passed_world, [7] ->
            send(owner, {:game_object_instance, passed_world})
            %Snapshot{world: passed_world, status: :available, fields: %{7 => {:ok, 0}}}
          end
        )

      assert context.instance_data.world == world
      assert_received {:game_object_instance, ^world}
    end

    test "keeps identical map IDs isolated by instance ID" do
      condition = %Condition{type: :instance_data, value1: 7, value2: 1}
      request = Request.new([], 0.0, script_conditions: [condition])

      lookup = fn world, [7] ->
        %Snapshot{world: world, status: :available, fields: %{7 => {:ok, world.instance_id}}}
      end

      first = AIEnvironment.context(mob(WorldRef.instance(329, 1)), 1_000, request, instance_data: lookup)
      second = AIEnvironment.context(mob(WorldRef.instance(329, 2)), 1_000, request, instance_data: lookup)

      assert first.instance_data.fields == %{7 => {:ok, 1}}
      assert second.instance_data.fields == %{7 => {:ok, 2}}
    end
  end

  defp put_actor(kind, guid, world, distance) do
    SpatialHash.update(kind, guid, world, distance, 0.0, 0.0)
    Metadata.put(guid, %{alive?: true, level: 10})
  end

  defp remove_actor(kind, guid) do
    SpatialHash.remove(kind, guid)
    Metadata.delete(guid)
  end

  defp start_line_of_sight_trace do
    test_pid = self()
    tracer = spawn_link(fn -> line_of_sight_tracer(0) end)
    :erlang.trace(test_pid, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Namigator, :line_of_sight, 7}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({Namigator, :line_of_sight, 7}, false, [])
    end)

    tracer
  end

  defp line_of_sight_call_count(tracer) do
    send(tracer, {:count, self()})

    receive do
      {:line_of_sight_call_count, count} ->
        send(tracer, :stop)
        count
    end
  end

  defp line_of_sight_tracer(count) do
    receive do
      {:trace, _pid, :call, {Namigator, :line_of_sight, _args}} ->
        line_of_sight_tracer(count + 1)

      {:count, caller} ->
        send(caller, {:line_of_sight_call_count, count})
        line_of_sight_tracer(count)

      :stop ->
        :ok
    end
  end

  defp mob(world) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 98_002)},
      unit: %Unit{target: 0, auras: []},
      internal: %Internal{world: world, threat: %{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp game_object(world) do
    %GameObject{
      object: %Object{guid: Guid.from_low_guid(:game_object, 1, 98_100)},
      game_object: %ThistleTea.Game.Entity.Data.Component.GameObject{},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
