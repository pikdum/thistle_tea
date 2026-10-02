defmodule ThistleTea.Game.World.Entity.ScriptRoutingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.Script.Request
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.GameObject, as: GameObjectComponent
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgEmote
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.GameObject, as: GameObjectServer
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Entity.ScriptExecution
  alias ThistleTea.Game.World.Loader.Emote, as: EmoteLoader
  alias ThistleTea.Game.World.Loader.Mob.Builder, as: MobBuilder
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.ServerVariables
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.ScriptedEvent, as: ScriptedEventSystem
  alias ThistleTea.Test.FactionFixtures
  alias ThistleTea.Test.Unique

  setup [{FactionFixtures, :seed}, :world]

  describe "script delivery" do
    test "reaction changes publish acquisition and assistance eligibility", %{world: world} do
      creature = mob(world, 0.0, 0.0)
      {:ok, pid} = World.start_entity(creature)
      on_exit(fn -> World.stop_entity(creature.object.guid) end)

      for {reaction, proximity?, assistance?} <- [{0, false, false}, {1, false, true}, {2, true, true}] do
        Entity.start_script(pid, [%ScriptStep{command: :set_react_state, datalong: reaction}], 0, world)
        :sys.get_state(pid)
        metadata = Metadata.get(creature.object.guid)
        assert metadata.proximity_aggro? == proximity?
        assert metadata.assistance_available? == assistance?
      end
    end

    test "zero emotes restore a creature after a persistent scripted animation", %{world: world} do
      previous = Enum.flat_map([0, 69], &:ets.lookup(EmoteLoader, {:animation, &1}))
      EmoteLoader.load([%{id: 0, spec_proc: 0}, %{id: 69, spec_proc: 2}], [])
      creature = mob(world, 0.0, 0.0)
      {:ok, pid} = World.start_entity(creature)

      on_exit(fn ->
        World.stop_entity(creature.object.guid)
        for id <- [0, 69], do: :ets.delete(EmoteLoader, {:animation, id})
        :ets.insert(EmoteLoader, previous)
      end)

      Entity.start_script(pid, [%ScriptStep{command: :emote, datalong: 69}], 0, world)
      assert :sys.get_state(pid).unit.npc_emote_state == 69
      Entity.start_script(pid, [%ScriptStep{command: :emote, datalong: 0}], 0, world)
      assert :sys.get_state(pid).unit.npc_emote_state == 0
      Entity.request_update_from(pid, self())
      guid = creature.object.guid

      assert_receive {:"$gen_cast", {:send_packet, %{object: %{guid: ^guid}, unit: %{npc_emote_state: 0}}}}
    end

    test "live creatures face each other and project a delayed swapped emote", %{world: world} do
      previous = :ets.lookup(EmoteLoader, {:animation, 1})
      EmoteLoader.load([%{id: 1, spec_proc: 0}], [])

      on_exit(fn ->
        :ets.delete(EmoteLoader, {:animation, 1})
        :ets.insert(EmoteLoader, previous)
      end)

      source = mob(world, 0.0, 0.0)
      target = mob(world, 3.0, 4.0)
      source_guid = source.object.guid
      target_guid = target.object.guid
      {:ok, source_pid} = World.start_entity(source)
      {:ok, target_pid} = World.start_entity(target)

      on_exit(fn ->
        World.stop_entity(source_guid)
        World.stop_entity(target_guid)
      end)

      steps = [
        %ScriptStep{command: :turn_to, swap_initial?: true},
        %ScriptStep{command: :emote, datalong: 1, delay_ms: 30, swap_initial?: true},
        %ScriptStep{command: :turn_to}
      ]

      Entity.start_script(source_pid, steps, target_guid, world)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgEmote{guid: ^target_guid, emote: 1}, _opts}}, 1_000
      refute_received {:"$gen_cast", {:send_packet, %SmsgEmote{guid: ^source_guid}, _opts}}
      assert_in_delta elem(:sys.get_state(source_pid).movement_block.position, 3), :math.atan2(4, 3), 0.0001
      assert_in_delta elem(:sys.get_state(target_pid).movement_block.position, 3), :math.atan2(-4, -3), 0.0001
      assert :sys.get_state(source_pid).internal.events == []
      assert :sys.get_state(target_pid).internal.events == []
    end

    test "forwarding carries the source world into the player owner", %{world: world} do
      guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(guid)
      character = character(guid, world)
      state = %State{guid: guid, character: character}
      step = %ScriptStep{command: :stand_state, datalong: 1}
      effect = Effects.forward_script_steps(guid, [step], 0)
      EventSink.emit(mob(world, 0.0, 0.0), effect)
      assert_received {:"$gen_cast", {:start_script, [^step], 0, ^world} = request}
      assert {:noreply, updated, {:continue, :maybe_broadcast_update}} = PlayerServer.handle_cast(request, state)
      assert updated.character.unit.stand_state == 1
      assert state.character.unit.stand_state == 0
    end

    test "receivers reject scripts from another instance", %{world: world} do
      other = WorldRef.instance(world.map_id, world.instance_id + 1)
      step = %ScriptStep{command: :emote, datalong: 1}
      player = %State{character: character(7, other)}
      creature = mob(other, 0.0, 0.0)
      object = %GameObject{internal: %Internal{world: other}}

      for {server, state} <- [{PlayerServer, player}, {MobServer, creature}, {GameObjectServer, object}] do
        assert {:noreply, ^state} = server.handle_cast({:start_script, [step], 0, world}, state)
        assert {:noreply, ^state} = server.handle_info({:ai_script_steps, [step], 0, world}, state)
      end
    end

    test "a player's pending script stays in its original world", %{world: world} do
      character = character(7, world)
      step = %ScriptStep{command: :emote, datalong: 1}
      EventSink.emit(character, Effects.script_steps([step], 0, 0), Context.new(self()))
      assert_receive {:ai_script_steps, [^step], 0, ^world} = message
      moved = %{character | internal: %{character.internal | world: WorldRef.open(1)}}
      state = %State{character: moved}
      assert {:noreply, ^state} = PlayerServer.handle_info(message, state)
    end

    test "game object recipients execute on their own process", %{world: world} do
      object = %GameObject{
        object: %Object{guid: Guid.runtime(:game_object, 21_145), entry: 21_145},
        game_object: %GameObjectComponent{state: 0, type_id: 0},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: world}
      }

      pid = start_supervised!({GameObjectServer, object})
      step = %ScriptStep{command: :set_game_object_state, datalong: 1}
      EventSink.emit(mob(world, 0.0, 0.0), Effects.forward_script_steps(object.object.guid, [step], 0))
      assert :sys.get_state(pid).game_object.state == 1
    end
  end

  describe "acknowledged scripts" do
    test "server variables are visible to the immediate tail and other worlds", %{world: world} do
      {source, source_pid} = start_mob(world)
      {_other, other_pid} = start_mob(WorldRef.instance(world.map_id, world.instance_id + 1_000_000))
      index = Unique.integer()
      on_exit(fn -> :ets.delete(ServerVariables, index) end)
      condition = %Condition{type: :saved_variable, value1: index, value2: 6}
      assign = %ScriptStep{command: :set_server_variable, datalong: index, datalong2: 6}
      steps = [assign, %{stand(1) | condition: condition, abort_on_failure?: true}, stand(2)]
      Entity.start_script(source_pid, steps, 0, world)
      assert finished_script(source_pid).unit.stand_state == 2
      assert ServerVariables.get(index) == 6
      World.stop_entity(source.object.guid)
      other_world = :sys.get_state(other_pid).internal.world
      Entity.start_script(other_pid, [%{stand(1) | condition: condition}], 0, other_world)
      assert finished_script(other_pid).unit.stand_state == 1
      assert ServerVariables.get(index) == 6
    end

    test "invalid variable assignments honor abort and preserve the previous value", %{world: world} do
      {_source, pid} = start_mob(world)
      index = Unique.integer()
      on_exit(fn -> :ets.delete(ServerVariables, index) end)
      ServerVariables.put(index, 7)

      for abort? <- [true, false] do
        assign = %ScriptStep{command: :set_server_variable, datalong: index, datalong2: -1, abort_on_failure?: abort?}
        Entity.start_script(pid, [stand(0), assign, stand(1)], 0, world)
        assert finished_script(pid).unit.stand_state == if(abort?, do: 0, else: 1)
        assert ServerVariables.get(index) == 7
      end
    end

    test "a remote termination or failed condition cancels the caller's immediate and delayed tail", %{world: world} do
      {source, source_pid} = start_mob(world)
      {target, target_pid} = start_mob(world)

      for command <- [
            %ScriptStep{command: :terminate_script},
            %ScriptStep{command: :stand_state, datalong: 1, condition: %Condition{type: :source_entry, value1: 999}}
          ] do
        step = %{command | swap_initial?: true, abort_on_failure?: true}
        Entity.start_script(source_pid, [step, stand(1), %{stand(2) | delay_ms: 20}], target.object.guid, world)
        finished = finished_script(source_pid)
        assert finished.unit.stand_state == source.unit.stand_state
        assert :sys.get_state(target_pid).unit.stand_state == target.unit.stand_state
        assert finished.internal.events == []
      end
    end

    test "missing or wrong-world recipients honor the abort flag", %{world: world} do
      {_source, source_pid} = start_mob(world)
      {target, _target_pid} = start_mob(WorldRef.instance(world.map_id, world.instance_id + 1_000_000))
      absent = Guid.runtime(:mob, 15_694)

      for recipient <- [target.object.guid, absent], abort? <- [true, false] do
        step = %{stand(2) | swap_initial?: true, abort_on_failure?: abort?}
        Entity.start_script(source_pid, [stand(0), step, stand(1)], recipient, world)
        assert finished_script(source_pid).unit.stand_state == if(abort?, do: 0, else: 1)
      end
    end

    test "a command can swap back to its caller without blocking either owner", %{world: world} do
      {_source, source_pid} = start_mob(world)
      {target, target_pid} = start_mob(world)
      step = %{stand(1) | swap_initial?: true, swap_final?: true}
      Entity.start_script(source_pid, [step, stand(2)], target.object.guid, world)
      assert finished_script(source_pid).unit.stand_state == 2
      assert :sys.get_state(target_pid).unit.stand_state == target.unit.stand_state
    end

    test "duplicate map-event starts stop the losing script before its tail", %{world: world} do
      {source, first} = start_mob(world)
      {_target, second} = start_mob(world)
      gate = %ScriptStep{command: :start_map_event, datalong: 648, datalong2: 60, abort_on_failure?: true}
      steps = [stand(0), gate, stand(1), %{stand(2) | delay_ms: 25}]

      on_exit(fn ->
        ScriptedEventSystem.command_result(
          Effects.scripted_event_command(world, source.object.guid, 0, %{gate | command: :end_map_event})
        )
      end)

      Entity.start_script(first, steps, 0, world)
      Entity.start_script(second, steps, 0, world)
      results = Enum.map([first, second], &finished_script/1)
      assert Enum.map(results, & &1.unit.stand_state) |> Enum.sort() == [0, 2]
      assert Enum.all?(results, &(&1.internal.events == []))
    end

    test "expired requests cannot mutate any entity owner", %{world: world} do
      request = %Request{
        id: make_ref(),
        world: world,
        step: stand(2),
        target_guid: 0,
        reply_to: self(),
        deadline: Time.now() - 1
      }

      object = %GameObject{internal: %Internal{world: world}}

      for actor <- [mob(world, 0.0, 0.0), character(7, world), object] do
        failed = ScriptExecution.command(actor, request)
        assert [%Effects.ScriptReply{request: ^request, status: :failed}] = failed.internal.events
        assert %{failed | internal: %{failed.internal | events: []}} == actor
      end
    end
  end

  defp stand(value), do: %ScriptStep{command: :stand_state, datalong: value}

  defp start_mob(world) do
    actor = mob(world, 0.0, 0.0)
    {:ok, pid} = World.start_entity(actor)
    on_exit(fn -> World.stop_entity(actor.object.guid) end)
    {actor, pid}
  end

  defp finished_script(pid, attempts \\ 200) do
    state = :sys.get_state(pid)

    if state.internal.scripts.runs == %{} or attempts == 0 do
      assert state.internal.scripts.runs == %{}
      state
    else
      Process.sleep(5)
      finished_script(pid, attempts - 1)
    end
  end

  defp world(_context) do
    world = WorldRef.instance(998, Unique.integer())
    observer = Guid.from_low_guid(:player, Unique.integer())
    {:ok, _} = Entity.register(observer)
    SpatialHash.update(:players, observer, world, 0.0, 0.0, 0.0)
    on_exit(fn -> SpatialHash.remove(:players, observer) end)
    %{world: world}
  end

  defp character(guid, world) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, stand_state: 0, auras: []},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world, spellbook: %{}}
    }
  end

  defp mob(world, x, y) do
    %Mangos.Creature{
      guid: Guid.low_guid(Guid.runtime(:mob, 15_694)),
      id: 15_694,
      position_x: x,
      position_y: y,
      selected_level: 1,
      curhealth: 100,
      creature_movement: [],
      creature_template: %Mangos.CreatureTemplate{
        entry: 15_694,
        name: "Reveler",
        min_level: 1,
        max_level: 1,
        faction_alliance: 35,
        extra_flags: 2,
        melee_base_attack_time: 2_000
      }
    }
    |> MobBuilder.build()
    |> then(&%{&1 | internal: %{&1.internal | world: world}})
  end
end
