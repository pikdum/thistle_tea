defmodule ThistleTea.Game.World.Entity.AIEnvironmentTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Blackboard.Navigation
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Entity.TargetRef
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.Possession
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.AIEnvironment
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding.Aquatic
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.ScriptedEvent
  alias ThistleTea.Game.World.System.ScriptedEvent.Event
  alias ThistleTea.Native.Namigator

  describe "move_to/4" do
    test "scripted point movement can take over a running patrol" do
      blackboard = %Blackboard{
        navigation: %Navigation{movement_override: :waypoint, target: {1.0, 2.0, 3.0}, move_target: {1.0, 2.0, 3.0}}
      }

      entity = %Mob{
        internal: %Internal{world: WorldRef.open(999), blackboard: blackboard},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      ordinary = AIEnvironment.move_to(entity, {4.0, 5.0, 6.0}, [], 1_000)
      assert ordinary.internal.blackboard == blackboard

      scripted = AIEnvironment.move_to(entity, {4.0, 5.0, 6.0}, [run?: true, stop_patrol?: true], 1_000)
      assert scripted.internal.blackboard.navigation.movement_override == :idle
      assert scripted.internal.blackboard.navigation.target == nil
      assert scripted.internal.blackboard.navigation.move_target == nil
    end
  end

  describe "context/3" do
    test "observes the active melee victim after selection is cleared" do
      world = WorldRef.open(999)
      target = Guid.runtime(:mob, 19)
      put_actor(:mobs, target, world, 130.0)
      on_exit(fn -> remove_actor(:mobs, target) end)

      character = %Character{
        object: %Object{guid: 98_206},
        unit: %Unit{target: 0},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: world,
          blackboard: Blackboard.enable_auto_attack(Blackboard.new(), %TargetRef{guid: target})
        }
      }

      perception = AIEnvironment.context(character, 1_000).perception
      assert Perception.position(perception, target) == {world, 130.0, 0.0, 0.0}
    end

    test "owners snapshot distant pet and direct combat references" do
      world = WorldRef.open(999)
      guid = Guid.runtime(:pet, 18)
      enemy = Guid.runtime(:mob, 19)
      direct = Guid.runtime(:mob, 20)

      for {actor, distance} <- [{guid, 100.0}, {enemy, 130.0}, {direct, 150.0}],
          do: put_actor(:mobs, actor, world, distance)

      Metadata.update(guid, %{owner_guid: 98_205, threat_refs: MapSet.new([{enemy, 7}])})

      on_exit(fn ->
        for actor <- [guid, enemy, direct], do: remove_actor(:mobs, actor)
      end)

      character = %Character{
        object: %Object{guid: 98_205},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: world,
          threat_refs: MapSet.new([{direct, 8}]),
          companion: %Companion{kind: :hunter_pet, status: {:active, %EntityRef{guid: guid, entry: 1, spell_id: 1}}}
        }
      }

      perception = AIEnvironment.context(character, 1_000).perception
      Metadata.update(guid, %{threat_refs: MapSet.new()})
      assert Perception.metadata(perception, guid).threat_refs == MapSet.new([{enemy, 7}])
      assert Perception.position(perception, enemy) == {world, 130.0, 0.0, 0.0}
      assert Perception.position(perception, direct) == {world, 150.0, 0.0, 0.0}
    end

    test "aggressive pets observe and check sight beyond twenty yards" do
      world = WorldRef.open(999)
      target_guid = Guid.from_low_guid(:mob, 1, 98_200)
      put_actor(:mobs, target_guid, world, 30.0)
      on_exit(fn -> remove_actor(:mobs, target_guid) end)
      tracer = start_call_trace({Namigator, :line_of_sight, 7})
      entity = mob(world)

      entity = %{
        entity
        | internal: %{
            entity.internal
            | pet: %Internal.Pet{kind: :guardian, reaction_state: :aggressive},
              creature: %Creature{detection_range: 20.0}
          }
      }

      perception = AIEnvironment.context(entity, 1_000).perception
      assert Perception.nearby(perception, :mobs, 45.0) == [{target_guid, 30.0}]
      assert call_count(tracer) == 1
    end

    test "snapshots the current player controller level without replacing creature level" do
      world = WorldRef.open(999)
      target_guid = Guid.from_low_guid(:mob, 1, 98_201)
      owner_guid = Guid.from_low_guid(:player, 98_202)
      charmer_guid = Guid.from_low_guid(:player, 98_203)
      put_actor(:mobs, target_guid, world, 10.0)
      Metadata.update(target_guid, %{owner_guid: owner_guid})
      Metadata.put(owner_guid, %{level: 60})
      Metadata.put(charmer_guid, %{level: 40})

      on_exit(fn ->
        remove_actor(:mobs, target_guid)
        Metadata.delete(owner_guid)
        Metadata.delete(charmer_guid)
      end)

      entity = mob(world)
      owned = AIEnvironment.context(entity, 1_000).perception
      assert Perception.aggro_level(owned, target_guid) == 60
      assert Perception.metadata(owned, target_guid).level == 10

      Metadata.update(target_guid, %{charmed_by: charmer_guid})
      charmed = AIEnvironment.context(entity, 2_000).perception
      assert Perception.aggro_level(charmed, target_guid) == 40
      assert Perception.aggro_level(owned, target_guid) == 60

      Metadata.update(charmer_guid, %{level: 41})
      assert Perception.aggro_level(AIEnvironment.context(entity, 3_000).perception, target_guid) == 41
      Metadata.delete(charmer_guid)
      assert Perception.aggro_level(AIEnvironment.context(entity, 4_000).perception, target_guid) == 10
    end

    @tag :namigator_maps
    test "prepares random movement regions for EventAI and explicit script continuations" do
      world = WorldRef.open(1)
      anchor = {-288.089, -1874.42, 92.743}
      step = %ScriptStep{command: :move_to, datalong: 3, position: Tuple.insert_at(anchor, 3, 5.0)}
      event = %AIEvent{event_type: :timer_ooc, actions: [[step]]}
      actor = mob(world)
      actor = %{actor | internal: %{actor.internal | creature: %Creature{ai_events: [event]}}}
      request = Request.new([], 0.0, random_points: [{{-219.482, -1930.82, 93.553}, 5.0}])
      context = AIEnvironment.context(actor, 0, request)
      assert map_size(context.navigation.random_points) == 2

      for {{1, {x, y, _}, radius}, point} <- context.navigation.random_points do
        assert {px, py, pz} = point
        assert :math.sqrt((px - x) ** 2 + (py - y) ** 2) <= radius
        assert pz > 90 and pz < 98
      end
    end

    test "a fighting pet observes distant owner opponents and player attackers as immutable snapshots" do
      world = WorldRef.open(999)
      owner = Guid.from_low_guid(:player, 98_201)
      attacker = Guid.runtime(:mob, 17)
      rival = Guid.from_low_guid(:player, 98_202)
      pet = mob(world)
      pet = %{pet | internal: %{pet.internal | in_combat: true, pet: %Internal.Pet{owner_guid: owner}}}
      put_actor(:players, owner, world, 150.0)
      put_actor(:mobs, attacker, world, 160.0)
      put_actor(:players, rival, world, 180.0)
      Metadata.update(owner, %{in_combat: true, combat_targets: [attacker], combat_victim_guid: attacker})
      Metadata.update(rival, %{in_combat: true, combat_victim_guid: owner})

      on_exit(fn ->
        remove_actor(:players, owner)
        remove_actor(:mobs, attacker)
        remove_actor(:players, rival)
      end)

      context = AIEnvironment.context(pet, 1_000)
      Metadata.update(owner, %{combat_targets: []})
      Metadata.update(rival, %{combat_victim_guid: nil})
      assert Perception.position(context.perception, attacker) == {world, 160.0, 0.0, 0.0}
      assert Perception.metadata(context.perception, owner).combat_targets == [attacker]
      assert Perception.metadata(context.perception, rival).combat_victim_guid == owner
    end

    test "a waiting pet observes incoming threat beyond its acquisition radius" do
      world = WorldRef.open(999)
      enemy = Guid.runtime(:mob, 17)
      pet = mob(world)
      pet = %{pet | internal: %{pet.internal | pet: %Internal.Pet{}, threat_refs: MapSet.new([{enemy, 7}])}}
      put_actor(:mobs, enemy, world, 160.0)
      Metadata.update(enemy, %{alive?: true, incarnation_id: 7, in_combat: true})
      on_exit(fn -> remove_actor(:mobs, enemy) end)

      context = AIEnvironment.context(pet, 1_000)
      assert Perception.position(context.perception, enemy) == {world, 160.0, 0.0, 0.0}
      assert Perception.metadata(context.perception, enemy).incarnation_id == 7
    end

    test "a charmed player observes its controller and every threat candidate" do
      world = WorldRef.open(999)
      caster = Guid.from_low_guid(:mob, 1, 98_190)
      target = Guid.from_low_guid(:player, 98_191)
      put_actor(:mobs, caster, world, 150.0)
      put_actor(:players, target, world, 160.0)
      Metadata.update(caster, %{combat_targets: [target], victim_guid: target})

      on_exit(fn ->
        remove_actor(:mobs, caster)
        remove_actor(:players, target)
      end)

      entity = %Character{
        object: %Object{guid: 98_192},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: world,
          possession: %Possession{
            caster_guid: caster,
            spell_id: 28_410,
            original_faction_template: 1,
            kind: :charm
          }
        }
      }

      context = AIEnvironment.context(entity, 1_000)
      Metadata.update(caster, %{combat_targets: []})
      assert Perception.position(context.perception, caster) == {world, 150.0, 0.0, 0.0}
      assert Perception.position(context.perception, target) == {world, 160.0, 0.0, 0.0}
      assert Perception.metadata(context.perception, caster).combat_targets == [target]
    end

    test "observes the fear caster beyond ordinary perception range" do
      actor_guid = Guid.from_low_guid(:player, 98_090)
      world = WorldRef.open(999)
      put_actor(:players, actor_guid, world, 150.0)
      on_exit(fn -> remove_actor(:players, actor_guid) end)

      holder = %Holder{
        caster_guid: actor_guid,
        auras: [%Aura{type: :mod_fear}]
      }

      entity = mob(world)
      entity = %{entity | unit: %{entity.unit | auras: [holder]}, internal: %{entity.internal | rooted?: true}}
      context = AIEnvironment.context(entity, 1_000)

      assert Perception.position(context.perception, actor_guid) == {world, 150.0, 0.0, 0.0}
      assert context.navigation.fear_point == nil
    end

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

      tracer = start_call_trace({Namigator, :line_of_sight, 7})

      mob = mob(world)
      mob = %{mob | unit: %{mob.unit | target: target_guid}, internal: %{mob.internal | in_combat: true}}
      perception = AIEnvironment.context(mob, 1_000).perception

      assert length(Perception.nearby(perception, :mobs, 2.0)) == 20
      assert call_count(tracer) == 1
    end

    test "an idle aggro check sights only nearby units it could attack" do
      world = %WorldRef{map_id: 999}
      creature = %FactionTemplate{id: 98_014, faction_group: 8, enemy_group: 1}
      mob = mob(world)
      mob = %{mob | internal: %{mob.internal | in_combat: false}}
      player_guid = Guid.from_low_guid(:player, 98_040)
      kin_guids = Enum.map(1..5, &Guid.from_low_guid(:mob, 1, 98_040 + &1))

      Metadata.put(mob.object.guid, %{alive?: true, level: 10, faction_template: creature})
      put_actor(:players, player_guid, world, 10.0)
      Metadata.put(player_guid, %{alive?: true, level: 10, faction_template: %FactionTemplate{id: 1, faction_group: 3}})

      for {guid, offset} <- Enum.with_index(kin_guids, 1) do
        put_actor(:mobs, guid, world, offset * 1.0)
        Metadata.put(guid, %{alive?: true, level: 10, faction_template: creature})
      end

      on_exit(fn ->
        Metadata.delete(mob.object.guid)
        remove_actor(:players, player_guid)
        Enum.each(kin_guids, &remove_actor(:mobs, &1))
      end)

      tracer = start_call_trace({Namigator, :line_of_sight, 7})
      perception = AIEnvironment.context(mob, 1_000).perception

      assert length(Perception.nearby(perception, :mobs, 10.0)) == 5
      assert Perception.nearby(perception, :players, 10.0) == [{player_guid, 10.0}]
      assert call_count(tracer) == 1
    end

    test "a swimming creature samples water only under units it could attack" do
      world = %WorldRef{map_id: 999}
      creature = %FactionTemplate{id: 98_015, faction_group: 8, enemy_group: 1}
      mob = mob(world)

      mob = %{
        mob
        | unit: %{mob.unit | display_id: 1},
          object: %{mob.object | scale_x: 1.0},
          internal: %{mob.internal | in_combat: false, creature: %Creature{inhabit_type: 3}}
      }

      player_guid = Guid.from_low_guid(:player, 98_050)
      kin_guids = Enum.map(1..5, &Guid.from_low_guid(:mob, 1, 98_050 + &1))

      Metadata.put(mob.object.guid, %{alive?: true, level: 10, faction_template: creature})
      put_actor(:players, player_guid, world, 10.0)
      Metadata.put(player_guid, %{alive?: true, level: 10, faction_template: %FactionTemplate{id: 1, faction_group: 3}})

      for {guid, offset} <- Enum.with_index(kin_guids, 1) do
        put_actor(:mobs, guid, world, offset * 1.0)
        Metadata.put(guid, %{alive?: true, level: 10, faction_template: creature})
      end

      on_exit(fn ->
        Metadata.delete(mob.object.guid)
        remove_actor(:players, player_guid)
        Enum.each(kin_guids, &remove_actor(:mobs, &1))
      end)

      tracer = start_call_trace({Aquatic, :water, 3})
      perception = AIEnvironment.context(mob, 1_000).perception

      assert length(Perception.nearby(perception, :mobs, 10.0)) == 5
      assert Perception.swimmable?(perception, player_guid) == false
      assert Enum.all?(kin_guids, &(Perception.swimmable?(perception, &1) == nil))
      assert call_count(tracer) == 1
    end

    test "reads the local clock only for local-time conditions" do
      world = WorldRef.open(0)
      local_time = %Condition{entry: 1, type: :local_time, value1: 0, value2: 0, value3: 23, value4: 59}

      assert AIEnvironment.context(mob(world), 1_000).condition_now == nil

      assert %NaiveDateTime{} =
               AIEnvironment.context(mob(world), 1_000, Request.new([], 0.0, script_conditions: [local_time])).condition_now
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
      assert context.script_conditions_by_target[victim_guid] == %{3 => :met}
    end

    test "selected targets receive their own immutable condition facts" do
      world = WorldRef.instance(999, 98_040)
      provided = Guid.from_low_guid(:player, 98_040)
      selected = Guid.from_low_guid(:player, 98_041)
      object = Guid.from_low_guid(:game_object, 21_145, 98_042)
      condition = %Condition{entry: 4, type: :nearby_game_object, value1: 21_145, value2: 10}
      put_actor(:players, provided, world, 100.0)
      put_actor(:players, selected, world, 5.0)
      SpatialHash.update(:game_objects, object, world, 6.0, 0.0, 0.0)

      on_exit(fn ->
        remove_actor(:players, provided)
        remove_actor(:players, selected)
        SpatialHash.remove(:game_objects, object)
      end)

      step = %ScriptStep{
        command: :emote,
        datalong: 1,
        target_type: :nearest_player,
        target_param1: 30,
        condition: condition
      }

      request = Request.new([provided], 30.0, script_conditions: [condition])
      entity = mob(world)
      entity = %{entity | internal: %{entity.internal | creature: %Creature{}}}
      context = AIEnvironment.context(entity, 1_000, request)
      assert context.script_conditions_by_target[provided] == %{4 => :unmet}
      assert context.script_conditions_by_target[selected] == %{4 => :met}
      SpatialHash.remove(:game_objects, object)
      {updated, _} = Script.run(entity, Blackboard.new(), [step], provided, context)
      assert [%Effects.Emote{emote_id: 1}] = updated.internal.events
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

  defp start_call_trace({module, _function, _arity} = mfa) do
    Code.ensure_loaded!(module)
    test_pid = self()
    tracer = spawn_link(fn -> call_tracer(0) end)
    :erlang.trace(test_pid, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern(mfa, true, [])

    on_exit(fn ->
      :erlang.trace_pattern(mfa, false, [])
    end)

    tracer
  end

  defp call_count(tracer) do
    send(tracer, {:count, self()})

    receive do
      {:call_count, count} ->
        send(tracer, :stop)
        count
    end
  end

  defp call_tracer(count) do
    receive do
      {:trace, _pid, :call, _mfa} ->
        call_tracer(count + 1)

      {:count, caller} ->
        send(caller, {:call_count, count})
        call_tracer(count)

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
      game_object: %ThistleTea.Game.Core.Entity.Component.GameObject{},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
