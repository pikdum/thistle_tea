defmodule ThistleTea.Game.Entity.Logic.AI.ScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.GameObject, as: GameObjectComponent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.GameObject, as: GameObjectEntity
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.WorldRef

  setup [:mob]

  describe "run/5" do
    test "talk enqueues a monster talk event plus the text emote", %{mob: mob} do
      step = %ScriptStep{
        command: :talk,
        texts: [%{text: "Hello there!", chat_type: :say, language: 0, emote_id: 5}]
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [
               %Effects.MonsterTalk{text: "Hello there!", chat_type: :say},
               %Effects.Emote{emote_id: 5}
             ] = mob.internal.events
    end

    test "emote enqueues an emote event", %{mob: mob} do
      step = %ScriptStep{command: :emote, datalong: 11}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.Emote{emote_id: 11}] = mob.internal.events
    end

    test "triggered self cast enqueues a trigger spell event", %{mob: mob} do
      step = %ScriptStep{command: :cast_spell, datalong: 12_544, datalong2: 0x02, target_self?: true}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      guid = mob.object.guid

      assert [%Effects.TriggerSpell{spell_id: 12_544, source_guid: ^guid, target_guid: ^guid}] =
               mob.internal.events
    end

    test "non-triggered casts use the real cast path, not the trigger pipeline", %{mob: mob} do
      # castflags 0x01 = interrupt_previous only (not triggered) → visible cast via
      # the mob casting machinery. With an empty fixture spellbook it finds no spell
      # and no-ops, but it must never fall back to the instant trigger pipeline.
      step = %ScriptStep{command: :cast_spell, datalong: 12_544, datalong2: 0x01, target_self?: true}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      refute Enum.any?(mob.internal.events, &is_struct(&1, Effects.TriggerSpell))
    end

    test "cast without a resolvable target is skipped", %{mob: mob} do
      step = %ScriptStep{command: :cast_spell, datalong: 12_544, target_type: :victim}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
    end

    test "set_phase variants mutate the blackboard phase", %{mob: mob} do
      blackboard = Blackboard.new()

      {_mob, blackboard} = Script.run(mob, blackboard, [%ScriptStep{command: :set_phase, datalong: 3}], nil, 0)
      assert blackboard.event_ai.phase == 3

      {_mob, blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_phase, datalong: 2, datalong2: 1}], nil, 0)

      assert blackboard.event_ai.phase == 5

      {_mob, blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_phase, datalong: 9, datalong2: 2}], nil, 0)

      assert blackboard.event_ai.phase == 0

      {_mob, blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_phase_range, datalong: 4, datalong2: 4}], nil, 0)

      assert blackboard.event_ai.phase == 4

      {_mob, blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_phase_random, datalong: 7, datalong2: 7}], nil, 0)

      assert blackboard.event_ai.phase == 7
    end

    test "flee marks the blackboard and emotes when a victim exists", %{mob: mob} do
      victim = Guid.from_low_guid(:player, 7)
      mob = %{mob | unit: %{mob.unit | target: victim}}

      {mob, blackboard} = Script.run(mob, Blackboard.new(), [%ScriptStep{command: :flee}], nil, 2_000)

      assert Blackboard.fleeing?(blackboard)
      assert blackboard.combat.flee_until == 2_000 + Script.flee_duration_ms()
      assert blackboard.combat.flee_from == victim
      assert [%Effects.MonsterTalk{chat_type: :text_emote}] = mob.internal.events
    end

    test "flee without a victim is ignored", %{mob: mob} do
      {mob, blackboard} = Script.run(mob, Blackboard.new(), [%ScriptStep{command: :flee}], nil, 2_000)

      refute Blackboard.fleeing?(blackboard)
      assert mob.internal.events == []
    end

    test "morph to a display id swaps the model and marks a broadcast", %{mob: mob} do
      step = %ScriptStep{command: :morph, datalong: 89, datalong2: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 89
      assert mob.internal.broadcast_update?
    end

    test "morph to zero restores the native display id", %{mob: mob} do
      mob = %{mob | unit: %{mob.unit | display_id: 89}}
      step = %ScriptStep{command: :morph, datalong: 0}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 11_354
      assert mob.internal.broadcast_update?
    end

    test "morph to the current display id is a no-op", %{mob: mob} do
      step = %ScriptStep{command: :morph, datalong: 11_354, datalong2: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 11_354
      refute mob.internal.broadcast_update?
    end

    test "morph by creature entry is skipped", %{mob: mob} do
      step = %ScriptStep{command: :morph, datalong: 6_578, datalong2: 0}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 11_354
      refute mob.internal.broadcast_update?
    end

    test "morph is skipped while dead", %{mob: mob} do
      mob = %{mob | unit: %{mob.unit | health: 0}}
      step = %ScriptStep{command: :morph, datalong: 89, datalong2: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 11_354
      refute mob.internal.broadcast_update?
    end

    test "set_run flips the running flag and persists run mode on the blackboard", %{mob: mob} do
      {mob, blackboard} =
        Script.run(mob, Blackboard.new(), [%ScriptStep{command: :set_run, datalong: 1}], nil, 1_000)

      assert mob.internal.running
      assert Blackboard.run_mode?(blackboard)

      {mob, blackboard} = Script.run(mob, blackboard, [%ScriptStep{command: :set_run, datalong: 0}], nil, 1_000)

      refute mob.internal.running
      refute Blackboard.run_mode?(blackboard)
    end

    test "steps with a failing condition are skipped", %{mob: mob} do
      failing = %Condition{type: :db_guid, value1: 12_345}

      step = %ScriptStep{command: :emote, datalong: 11, condition: failing}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
    end

    test "summon_creature enqueues a summon event with explicit coordinates", %{mob: mob} do
      step = %ScriptStep{
        command: :summon_creature,
        datalong: 1_500,
        datalong2: 30_000,
        dataint: 0x01,
        dataint3: -1,
        dataint4: 3,
        position: {10.0, 20.0, 30.0, 1.5}
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.SummonCreature{summon: summon, steps: []}] = mob.internal.events
      assert summon.entry == 1_500
      assert summon.despawn_delay_ms == 30_000
      assert summon.despawn_type == 3
      assert summon.run?
      refute summon.unique?
      assert summon.position == {10.0, 20.0, 30.0, 1.5}
      assert summon.attack_guid == nil
    end

    test "summon_creature falls back to the summoner position and resolves the attack target", %{mob: mob} do
      victim = Guid.from_low_guid(:player, 9)

      mob = %{
        mob
        | unit: %{mob.unit | target: victim},
          movement_block: %{mob.movement_block | position: {5.0, 6.0, 7.0, 0.5}}
      }

      sub_steps = [%ScriptStep{command: :emote, datalong: 11}]

      step = %ScriptStep{
        command: :summon_creature,
        datalong: 1_500,
        dataint2: 777,
        dataint3: 1,
        position: {0.0, 0.0, 0.0, 0.0},
        sub_scripts: %{777 => sub_steps}
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.SummonCreature{summon: summon, steps: ^sub_steps}] = mob.internal.events
      assert summon.position == {5.0, 6.0, 7.0, 0.5}
      assert summon.attack_guid == victim
    end

    test "despawn enqueues a despawn_self event with seconds-scaled respawn delay", %{mob: mob} do
      step = %ScriptStep{command: :despawn, datalong: 2_000, datalong2: 30}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.DespawnSelf{duration_ms: 2_000, respawn_delay_ms: 30_000}] = mob.internal.events
    end

    test "attack_start targets the victim and skips without one", %{mob: mob} do
      step = %ScriptStep{command: :attack_start, target_type: :victim}

      {idle, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)
      assert idle.internal.events == []

      victim = Guid.from_low_guid(:player, 9)
      mob = %{mob | unit: %{mob.unit | target: victim}}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)
      assert [%Effects.StartAttack{target_guid: ^victim}] = mob.internal.events
    end

    test "send_taxi_path targets a player through a semantic effect", %{mob: mob} do
      player_guid = Guid.from_low_guid(:player, 9)
      step = %ScriptStep{command: :send_taxi_path, datalong: 315}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], player_guid, 1_000)

      assert [%Effects.SendTaxiPath{target_guid: ^player_guid, path_id: 315}] = mob.internal.events
    end

    test "start_script runs the chosen resolved sub-script", %{mob: mob} do
      sub_steps = [%ScriptStep{command: :emote, datalong: 11}]

      step = %ScriptStep{
        command: :start_script,
        datalong: 555,
        dataint: 100,
        sub_scripts: %{555 => sub_steps}
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.Emote{emote_id: 11}] = mob.internal.events
    end

    test "stand_state updates the unit and marks a broadcast", %{mob: mob} do
      step = %ScriptStep{command: :stand_state, datalong: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.stand_state == 1
      assert mob.internal.broadcast_update?
    end

    test "mount sets and clears the mount display id", %{mob: mob} do
      step = %ScriptStep{command: :mount, datalong: 2_404, datalong2: 1}

      {mob, blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)
      assert mob.unit.mount_display_id == 2_404

      {mob, _blackboard} = Script.run(mob, blackboard, [%ScriptStep{command: :mount, datalong: 0}], nil, 1_000)
      assert mob.unit.mount_display_id == 0
    end

    test "mount by unresolved creature entry is skipped", %{mob: mob} do
      step = %ScriptStep{command: :mount, datalong: 14, datalong2: 0}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.mount_display_id == nil
      refute mob.internal.broadcast_update?
    end

    test "turn_to an orientation faces in place and enqueues a facing event", %{mob: mob} do
      step = %ScriptStep{command: :turn_to, datalong: 1, position: {0.0, 0.0, 0.0, 2.5}}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert {_x, _y, _z, 2.5} = mob.movement_block.position
      assert [%Effects.SetFacing{facing: {:angle, 2.5}}] = mob.internal.events
    end

    test "turn_to the victim enqueues a facing-target event", %{mob: mob} do
      victim = Guid.from_low_guid(:player, 9)
      mob = %{mob | unit: %{mob.unit | target: victim}}

      step = %ScriptStep{command: :turn_to, datalong: 0, target_type: :victim}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.SetFacing{facing: {:target, ^victim}}] = mob.internal.events
    end

    test "play_sound picks the object-sound variant for distance-dependent flags", %{mob: mob} do
      steps = [
        %ScriptStep{command: :play_sound, datalong: 6_943},
        %ScriptStep{command: :play_sound, datalong: 6_944, datalong2: 0x2}
      ]

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), steps, nil, 1_000)

      assert [
               %Effects.PlaySound{sound_id: 6_943},
               %Effects.PlayObjectSound{sound_id: 6_944}
             ] = mob.internal.events
    end

    test "swap-final steps are forwarded to the resolved buddy", %{mob: mob} do
      buddy = Guid.from_low_guid(:mob, 10_616, 81_251)

      step = %ScriptStep{
        command: :talk,
        target_type: :creature_with_guid,
        target_param1: 81_251,
        buddy_guid: buddy,
        swap_final?: true,
        texts: [%{text: "Back to work!", chat_type: :say, language: 0, emote_id: 0}]
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      self_guid = mob.object.guid

      assert [
               %Effects.ForwardScriptSteps{target_guid: ^buddy, source_guid: ^self_guid, steps: [forwarded]}
             ] = mob.internal.events

      assert forwarded.command == :talk
      assert forwarded.target_type == :provided
      refute forwarded.swap_final?
    end

    test "swap-final steps with an unresolved buddy are skipped", %{mob: mob} do
      step = %ScriptStep{
        command: :talk,
        target_type: :creature_with_guid,
        target_param1: 81_251,
        swap_final?: true,
        texts: [%{text: "Back to work!", chat_type: :say, language: 0, emote_id: 0}]
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
    end

    test "swap-final steps resolving to self execute locally", %{mob: mob} do
      step = %ScriptStep{
        command: :emote,
        datalong: 11,
        target_type: :creature_with_guid,
        buddy_guid: mob.object.guid,
        swap_final?: true
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.Emote{emote_id: 11}] = mob.internal.events
    end

    test "swap-initial steps are skipped", %{mob: mob} do
      step = %ScriptStep{command: :emote, datalong: 11, swap_initial?: true}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
    end

    test "turn_to faces a guid-selected buddy", %{mob: mob} do
      buddy = Guid.from_low_guid(:mob, 10_616, 81_251)

      step = %ScriptStep{
        command: :turn_to,
        datalong: 0,
        target_type: :creature_with_guid,
        buddy_guid: buddy
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.SetFacing{facing: {:target, ^buddy}}] = mob.internal.events
    end

    test "quest_explored enqueues group event credit with distance context", %{mob: mob} do
      player_guid = Guid.from_low_guid(:player, 9)
      world_object_guid = mob.object.guid
      step = %ScriptStep{command: :quest_explored, datalong: 986, datalong2: 80, datalong3: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], player_guid, 1_000)

      assert [
               %Effects.QuestEventCredit{
                 player_guid: ^player_guid,
                 quest_id: 986,
                 group?: true,
                 distance: 80,
                 world_object_guid: ^world_object_guid
               }
             ] = mob.internal.events
    end

    test "kill_credit enqueues scripted creature credit", %{mob: mob} do
      player_guid = Guid.from_low_guid(:player, 9)
      step = %ScriptStep{command: :kill_credit, datalong: 11_220, datalong2: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], player_guid, 1_000)

      assert [
               %Effects.QuestKillCredit{
                 player_guid: ^player_guid,
                 creature_entry: 11_220,
                 group?: true
               }
             ] = mob.internal.events
    end

    test "fail_quest enqueues group quest failure", %{mob: mob} do
      player_guid = Guid.from_low_guid(:player, 9)
      step = %ScriptStep{command: :fail_quest, datalong: 986}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], player_guid, 1_000)

      assert [%Effects.QuestFail{player_guid: ^player_guid, quest_id: 986, group?: true}] =
               mob.internal.events
    end

    test "quest_credit enqueues interaction credit for the world object", %{mob: mob} do
      player_guid = Guid.from_low_guid(:player, 9)
      world_object_guid = mob.object.guid
      step = %ScriptStep{command: :quest_credit}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], player_guid, 1_000)

      assert [
               %Effects.QuestInteractionCredit{
                 player_guid: ^player_guid,
                 target_guid: ^world_object_guid
               }
             ] = mob.internal.events
    end

    test "start_waypoints installs the selected route and initial delay", %{mob: mob} do
      route = %WaypointRoute{
        first_point: 1,
        destination_point: 1,
        points: %{1 => %Waypoint{}, 2 => %Waypoint{}}
      }

      context =
        Context.new(1_000,
          waypoints: Waypoints.new(%{{:special, 7_784} => route})
        )

      step = %ScriptStep{
        command: :start_waypoints,
        datalong: 3,
        datalong2: 2,
        datalong3: 500,
        datalong4: 0,
        dataint2: 7_784
      }

      {_mob, blackboard} = Script.run(mob, Blackboard.new(), [step], nil, context)

      assert %WaypointRoute{destination_point: 2, repeat?: false} =
               blackboard.navigation.scripted_waypoint_route

      assert blackboard.navigation.next_waypoint_at == 1_500
    end

    test "map event commands enqueue a world-system request", %{mob: mob} do
      player_guid = Guid.from_low_guid(:player, 9)
      step = %ScriptStep{command: :start_map_event, datalong: 648, datalong2: 2_400}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], player_guid, 1_000)

      assert [
               %Effects.ScriptedEventCommand{
                 source_guid: source_guid,
                 target_guid: ^player_guid,
                 step: ^step
               }
             ] = mob.internal.events

      assert source_guid == mob.object.guid
    end

    test "modify_flags changes typed unit and npc flag fields", %{mob: mob} do
      steps = [
        %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x200, datalong3: 1},
        %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x2, datalong3: 2}
      ]

      mob = %{mob | unit: %{mob.unit | flags: 0x100, npc_flags: 0x3}}
      {mob, _blackboard} = Script.run(mob, Blackboard.new(), steps, nil, 1_000)

      assert mob.unit.flags == 0x300
      assert mob.unit.npc_flags == 0x1
      assert mob.internal.broadcast_update?
    end

    test "modify_flags changes game object interaction flags" do
      game_object = %GameObjectEntity{
        object: %Object{guid: Guid.from_low_guid(:game_object, 1, 1)},
        game_object: %GameObjectComponent{flags: 0x10},
        internal: %Internal{}
      }

      step = %ScriptStep{command: :modify_flags, datalong: 9, datalong2: 0x10, datalong3: 2}
      {game_object, _blackboard} = Script.run(game_object, Blackboard.new(), [step], nil, 1_000)

      assert game_object.game_object.flags == 0
      assert game_object.internal.broadcast_update?
    end

    test "set_faction applies and explicitly restores a scripted faction", %{mob: mob} do
      mob = %{mob | unit: %{mob.unit | faction_template: 35}}
      set = %ScriptStep{command: :set_faction, datalong: 113, datalong2: 1}

      {mob, blackboard} = Script.run(mob, Blackboard.new(), [set], nil, 1_000)
      assert mob.unit.faction_template == 113

      clear = %ScriptStep{command: :set_faction, datalong: 0}
      {mob, _blackboard} = Script.run(mob, blackboard, [clear], nil, 1_000)
      assert mob.unit.faction_template == 35
    end

    test "summon_object reuses the semantic game object summon effect", %{mob: mob} do
      step = %ScriptStep{
        command: :summon_object,
        datalong: 21_145,
        datalong2: 300,
        position: {-9084.64, 830.321, 109.609, 0.541051}
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [
               %Effects.SummonGameObject{
                 entry: 21_145,
                 duration_ms: 300_000,
                 position: {-9084.64, 830.321, 109.609, 0.541051}
               }
             ] = mob.internal.events
    end

    test "game object state and animation commands stay typed" do
      game_object = %GameObjectEntity{
        object: %Object{guid: Guid.from_low_guid(:game_object, 1, 1)},
        game_object: %GameObjectComponent{state: 0},
        internal: %Internal{}
      }

      steps = [
        %ScriptStep{command: :set_game_object_state, datalong: 2},
        %ScriptStep{command: :play_custom_animation, datalong: 1}
      ]

      {game_object, _blackboard} = Script.run(game_object, Blackboard.new(), steps, nil, 1_000)

      assert game_object.game_object.state == 2
      assert game_object.internal.broadcast_update?
      assert [%Effects.GameObjectCustomAnimation{animation: 1}] = game_object.internal.events
    end

    test "activate_object requests owner-local game object use" do
      user_guid = Guid.from_low_guid(:player, 9)

      game_object = %GameObjectEntity{
        object: %Object{guid: Guid.from_low_guid(:game_object, 1, 1)},
        game_object: %GameObjectComponent{state: 0},
        internal: %Internal{}
      }

      {game_object, _blackboard} =
        Script.run(
          game_object,
          Blackboard.new(),
          [%ScriptStep{command: :activate_object}],
          user_guid,
          1_000
        )

      assert [%Effects.ActivateGameObject{user_guid: ^user_guid}] = game_object.internal.events
    end

    test "game object spawn lifecycle commands enqueue boundary effects", %{mob: mob} do
      blueprint = %GameObjectEntity{
        object: %Object{guid: Guid.from_low_guid(:game_object, 1_000, 22)},
        game_object: %GameObjectComponent{state: 0},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }

      steps = [
        %ScriptStep{
          command: :respawn_game_object,
          datalong2: 2,
          game_object_spawn: blueprint
        },
        %ScriptStep{
          command: :despawn_game_object,
          datalong2: 30,
          game_object_spawn: blueprint
        },
        %ScriptStep{
          command: :load_game_object_spawn,
          game_object_spawn: blueprint
        }
      ]

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), steps, nil, 1_000)

      assert [
               %Effects.RespawnGameObject{blueprint: ^blueprint, duration_ms: 5_000},
               %Effects.DespawnGameObject{blueprint: ^blueprint, respawn_delay_ms: 30_000},
               %Effects.LoadGameObjectSpawn{blueprint: ^blueprint}
             ] = mob.internal.events
    end

    test "nearest game object commands are forwarded to the object owner", %{mob: mob} do
      game_object_guid = Guid.from_low_guid(:game_object, 1_000, 22)

      perception =
        Perception.new(
          1_000,
          nil,
          %{},
          %{mobs: [], players: [], game_objects: [{game_object_guid, 5.0}]}
        )

      context = Context.new(1_000, perception: perception)

      step = %ScriptStep{
        command: :activate_object,
        target_type: :nearest_game_object_with_entry,
        target_param1: 1_000,
        target_param2: 10
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, context)

      assert [%Effects.ForwardScriptSteps{target_guid: ^game_object_guid, steps: [forwarded]}] =
               mob.internal.events

      assert forwarded.command == :activate_object
      assert forwarded.target_type == :provided
    end

    test "reports nested game object observation radius" do
      nested = %ScriptStep{
        command: :remove_object,
        target_type: :nearest_game_object_with_entry,
        target_param2: 45
      }

      step = %ScriptStep{sub_scripts: %{1 => [nested]}}

      assert Script.game_object_observation_radius([step]) == 45
      assert Script.observation_radius([step]) == 45
    end

    test "add_aura uses the trigger spell pipeline", %{mob: mob} do
      step = %ScriptStep{command: :add_aura, datalong: 11_048}
      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      guid = mob.object.guid
      assert [%Effects.TriggerSpell{source_guid: ^guid, target_guid: ^guid, spell_id: 11_048}] = mob.internal.events
    end

    test "respawn_creature enqueues an owner lifecycle request", %{mob: mob} do
      step = %ScriptStep{command: :respawn_creature, datalong: 1}
      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Effects.RespawnSelf{even_if_alive?: true}] = mob.internal.events
    end

    test "create_item targets the player participating in the script", %{mob: mob} do
      player_guid = Guid.from_low_guid(:player, 9)
      step = %ScriptStep{command: :create_item, datalong: 22_048, datalong2: 1}
      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], player_guid, 1_000)

      assert [%Effects.GiveItem{target_guid: ^player_guid, item_id: 22_048, count: 1}] = mob.internal.events
    end

    test "set_default_movement updates the spawn movement policy", %{mob: mob} do
      spawn = %Spawn{distance: 0, movement_type: 0}
      mob = %{mob | internal: %{mob.internal | spawn: spawn}}
      step = %ScriptStep{command: :set_default_movement, datalong: 1, datalong3: 12}
      blackboard = Blackboard.idle_movement(Blackboard.new())

      {mob, blackboard} = Script.run(mob, blackboard, [step], nil, Context.new(1_000))

      assert mob.internal.spawn.movement_type == 1
      assert mob.internal.spawn.distance == 12
      assert blackboard.navigation.movement_override == nil
    end

    test "movement idle halts the active spline and overrides spawn movement", %{mob: mob} do
      mob = active_movement(mob)
      step = %ScriptStep{command: :movement, datalong: 0}

      {mob, blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.movement_block.spline_nodes == []
      assert [%Effects.MovementStopped{}] = mob.internal.events
      assert blackboard.navigation.movement_override == :idle
    end

    test "movement random stores the selected runtime anchor and radius", %{mob: mob} do
      spawn = %Spawn{position: {1.0, 2.0, 3.0}, distance: 5, movement_type: 0}
      mob = %{mob | internal: %{mob.internal | spawn: spawn}}
      mob = %{mob | movement_block: %{mob.movement_block | position: {10.0, 20.0, 30.0, 0.0}}}
      step = %ScriptStep{command: :movement, datalong: 1, datalong2: 1, position: {8.5, 0.0, 0.0, 0.0}}

      {_mob, blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert blackboard.navigation.movement_override == :random
      assert blackboard.navigation.wander_anchor == {10.0, 20.0, 30.0}
      assert blackboard.navigation.wander_radius == 8.5
      assert blackboard.navigation.next_wander_at == 0
    end

    test "movement waypoint resolves its start point and repeat policy", %{mob: mob} do
      spawn = %Spawn{position: {0.0, 0.0, 0.0}, movement_type: 0}
      mob = %{mob | internal: %{mob.internal | spawn: spawn}}

      route = %WaypointRoute{
        first_point: 1,
        destination_point: 1,
        points: %{
          1 => %Waypoint{position: {1.0, 0.0, 0.0, nil}},
          2 => %Waypoint{position: {2.0, 0.0, 0.0, nil}}
        }
      }

      waypoints = Waypoints.new(%{{:guid, Guid.low_guid(mob.object.guid)} => route})
      step = %ScriptStep{command: :movement, datalong: 2, datalong2: 0, datalong3: 2}

      {_mob, blackboard} =
        Script.run(mob, Blackboard.new(), [step], nil, Context.new(1_000, waypoints: waypoints))

      assert blackboard.navigation.movement_override == :waypoint
      assert blackboard.navigation.scripted_waypoint_route.destination_point == 2
      refute blackboard.navigation.scripted_waypoint_route.repeat?
    end

    test "movement home records a temporary home target", %{mob: mob} do
      spawn = %Spawn{position: {1.0, 2.0, 3.0}, movement_type: 1, distance: 5}
      mob = %{mob | internal: %{mob.internal | spawn: spawn}}
      step = %ScriptStep{command: :movement, datalong: 7}

      {_mob, blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert blackboard.navigation.movement_override == :home
      assert blackboard.navigation.target == {1.0, 2.0, 3.0}
    end

    test "movement commands are ignored while dead", %{mob: mob} do
      mob = %{mob | unit: %{mob.unit | health: 0}}
      blackboard = Blackboard.new()

      assert {^mob, ^blackboard} =
               Script.run(mob, blackboard, [%ScriptStep{command: :movement, datalong: 1}], nil, 1_000)
    end

    test "interrupt_casts cancels the selected active spell", %{mob: mob} do
      casting = %Cast{spell: %Spell{id: 22_313}, channel_ms: 0}
      mob = %{mob | internal: %{mob.internal | casting: casting}}

      {mob, _blackboard} =
        Script.run(mob, Blackboard.new(), [%ScriptStep{command: :interrupt_casts, datalong2: 22_313}], nil, 1_000)

      assert mob.internal.casting == nil
    end

    test "interrupt_casts preserves a different active spell", %{mob: mob} do
      casting = %Cast{spell: %Spell{id: 22_313}, channel_ms: 0}
      mob = %{mob | internal: %{mob.internal | casting: casting}}

      {mob, _blackboard} =
        Script.run(mob, Blackboard.new(), [%ScriptStep{command: :interrupt_casts, datalong2: 1}], nil, 1_000)

      assert mob.internal.casting == casting
    end

    test "set_home_position supports current, provided, and default homes", %{mob: mob} do
      original = %MovementBlock{position: {1.0, 2.0, 3.0, 0.5}}
      spawn = %Spawn{movement_block: original, position: {1.0, 2.0, 3.0}, home_orientation: 0.5}

      mob = %{
        mob
        | movement_block: %{mob.movement_block | position: {4.0, 5.0, 6.0, 1.5}},
          internal: %{mob.internal | spawn: spawn}
      }

      {mob, blackboard} =
        Script.run(mob, Blackboard.new(), [%ScriptStep{command: :set_home_position, datalong: 1}], nil, 1_000)

      assert mob.internal.spawn.position == {4.0, 5.0, 6.0}
      assert mob.internal.spawn.home_orientation == 1.5

      provided = %ScriptStep{command: :set_home_position, datalong: 0, position: {7.0, 8.0, 9.0, 2.5}}
      {mob, blackboard} = Script.run(mob, blackboard, [provided], nil, 1_000)

      assert mob.internal.spawn.position == {7.0, 8.0, 9.0}
      assert mob.internal.spawn.home_orientation == 2.5

      {mob, _blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_home_position, datalong: 2}], nil, 1_000)

      assert mob.internal.spawn.position == {1.0, 2.0, 3.0}
      assert mob.internal.spawn.home_orientation == 0.5
    end

    test "remove_object requests removal of its script owner", %{mob: mob} do
      {mob, _blackboard} =
        Script.run(mob, Blackboard.new(), [%ScriptStep{command: :remove_object}], nil, 1_000)

      assert [%Effects.RemoveSelf{respawn_delay_ms: nil}] = mob.internal.events
    end

    test "set_sheath updates the unit field", %{mob: mob} do
      {mob, _blackboard} =
        Script.run(mob, Blackboard.new(), [%ScriptStep{command: :set_sheath, datalong: 1}], nil, 1_000)

      assert mob.unit.sheath_state == 1
      assert mob.internal.broadcast_update?
    end

    test "combat_stop clears mob combat ownership", %{mob: mob} do
      target = Guid.from_low_guid(:player, 55)

      mob = %{
        mob
        | unit: %{mob.unit | target: target},
          internal: %{mob.internal | in_combat: true, threat: %{target => 10.0}}
      }

      {mob, blackboard} =
        Script.run(mob, Blackboard.new(), [%ScriptStep{command: :combat_stop}], nil, 1_000)

      refute mob.internal.in_combat
      assert mob.internal.threat == %{}
      assert mob.unit.target == 0
      assert blackboard == mob.internal.blackboard
    end

    test "combat_stop disengages a player from referenced mobs" do
      player_guid = Guid.from_low_guid(:player, 55)
      mob_guid = Guid.from_low_guid(:mob, 589, 2)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{target: mob_guid, flags: 0},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          in_combat: true,
          threat_refs: MapSet.new([{mob_guid, 1}]),
          blackboard: Blackboard.new()
        }
      }

      {character, _blackboard} =
        Script.run(character, Blackboard.new(), [%ScriptStep{command: :combat_stop}], mob_guid, 1_000)

      refute character.internal.in_combat
      assert character.internal.threat_refs == MapSet.new()
      assert character.unit.target == 0
      assert Enum.any?(character.internal.events, &is_struct(&1, Effects.DropThreat))
    end

    test "delayed steps are deferred through a script_steps event", %{mob: mob} do
      immediate = %ScriptStep{command: :emote, datalong: 11}
      delayed = %ScriptStep{command: :emote, datalong: 22, delay_ms: 4_000}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [immediate, delayed], nil, 1_000)

      assert [
               %Effects.Emote{emote_id: 11},
               %Effects.ScriptSteps{steps: [^delayed], duration_ms: 4_000}
             ] = mob.internal.events
    end

    test "unsupported commands are skipped", %{mob: mob} do
      step = %ScriptStep{command: {:unsupported, 10}}

      {mob, blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
      assert blackboard == Blackboard.new()
    end
  end

  defp mob(_context) do
    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 589, 1)},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 14,
        target: 0,
        auras: [],
        display_id: 11_354,
        native_display_id: 11_354
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        name: "Defias Pillager",
        in_combat: false,
        creature: %Creature{},
        spellbook: %{}
      }
    }

    {:ok, mob: mob}
  end

  defp active_movement(%Mob{} = mob) do
    movement_block = %{
      mob.movement_block
      | duration: 10_000,
        spline_nodes: [{10.0, 0.0, 0.0}],
        spline_id: 1
    }

    internal = %{
      mob.internal
      | movement_start_time: 0,
        movement_start_position: {0.0, 0.0, 0.0}
    }

    %{mob | movement_block: movement_block, internal: internal}
  end
end
