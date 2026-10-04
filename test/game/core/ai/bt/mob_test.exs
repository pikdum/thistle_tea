defmodule ThistleTea.Game.Core.AI.BT.MobTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.BehaviorRunner
  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Navigation, as: NavigationContext
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Core.AI.BT.WaypointHold
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Combat.Threat
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Loot
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.Internal.Waypoint
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Combat.ThreatSelection
  alias ThistleTea.Game.World.Entity.AIEnvironment
  alias ThistleTea.Game.World.Entity.NavigationResolver
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position.Spline
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  describe "reached_home" do
    test "restores a scripted home orientation" do
      home = {0.0, 0.0, 0.0}
      spawn = %Spawn{position: home, home_orientation: 1.25}

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{move_target: home, returning_home?: true}
      }

      mob =
        fixture_mob(position: {0.0, 0.0, 0.0, 0.0}, spline_nodes: [])
        |> then(&%{&1 | internal: %{&1.internal | spawn: spawn}})
        |> BT.init(MobBT.tree(), blackboard)

      assert {:success, mob} =
               BehaviorRunner.tick(MobBT.tree(), mob, Context.new(1_000))

      assert mob.movement_block.position == {0.0, 0.0, 0.0, 1.25}
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.SetFacing))
    end

    test "casts a reached_home self spell like Wastewander stealth" do
      victim = Guid.from_low_guid(:player, 998)
      Metadata.put(victim, %{alive?: false})
      on_exit(fn -> Metadata.delete(victim) end)

      stealth = %Spell{
        id: 22_766,
        name: "Stealth",
        school: :physical,
        cast_time_ms: 0,
        range_yards: 0.0,
        mana_cost: 0,
        power_type: 0,
        attributes: MapSet.new(),
        effects: []
      }

      cast = %ScriptStep{command: :cast_spell, datalong: 22_766, datalong2: 0, target_self?: true}
      event = %AIEvent{id: 1, event_type: :reached_home, chance: 100, actions: [[cast]]}

      mob = %Mob{
        object: %Object{guid: mob_guid(78)},
        unit: %Unit{health: 100, max_health: 100, level: 10, target: victim, auras: [], flags: 0},
        movement_block: %MovementBlock{
          position: {0.0, 0.0, 0.0, 0.0},
          walk_speed: 2.5,
          run_speed: 7.0
        },
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          in_combat: true,
          creature: %Creature{ai_events: [event]},
          spawn: %Spawn{position: {0.0, 0.0, 0.0}, movement_type: 1, distance: 5.0},
          spellbook: %{22_766 => stealth}
        }
      }

      mob = BT.init(mob, MobBT.tree())

      mob =
        Enum.reduce_while(1..10, mob, fn _i, mob ->
          mob = Movement.sync_position(mob, Time.now())
          {_status, mob} = BehaviorRunner.tick(mob.internal.behavior_tree, mob, AIEnvironment.context(mob, 1_000))
          mob = NavigationResolver.resolve(mob, 1_000)

          if Enum.any?(mob.internal.events, &is_struct(&1, Effects.SpellStart)) do
            {:halt, mob}
          else
            {:cont, finish_current_move(mob)}
          end
        end)

      assert Enum.any?(mob.internal.events, &(is_struct(&1, Effects.SpellStart) and &1.spell_id == 22_766))
    end

    test "fires the reached_home event after combat ends with a dead target" do
      victim = Guid.from_low_guid(:player, 999)
      Metadata.put(victim, %{alive?: false})
      on_exit(fn -> Metadata.delete(victim) end)

      talk = %ScriptStep{
        command: :talk,
        texts: [%{text: "Home again.", chat_type: :say, language: 0, emote_id: 0}]
      }

      event = %AIEvent{id: 1, event_type: :reached_home, chance: 100, actions: [[talk]]}

      mob = %Mob{
        object: %Object{guid: mob_guid(77)},
        unit: %Unit{health: 100, max_health: 100, level: 10, target: victim, auras: [], flags: 0},
        movement_block: %MovementBlock{
          position: {0.0, 0.0, 0.0, 0.0},
          walk_speed: 2.5,
          run_speed: 7.0
        },
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          in_combat: true,
          creature: %Creature{ai_events: [event]},
          spawn: %Spawn{
            movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 2.5}},
            position: {0.0, 0.0, 0.0},
            movement_type: 1,
            distance: 5.0
          },
          spellbook: %{}
        }
      }

      mob = BT.init(mob, MobBT.tree())

      mob =
        Enum.reduce_while(1..10, mob, fn _i, mob ->
          mob = Movement.sync_position(mob, Time.now())
          {_status, mob} = BehaviorRunner.tick(mob.internal.behavior_tree, mob, AIEnvironment.context(mob, 1_000))
          mob = NavigationResolver.resolve(mob, 1_000)

          if Enum.any?(mob.internal.events, &is_struct(&1, Effects.MonsterTalk)) do
            {:halt, mob}
          else
            {:cont, finish_current_move(mob)}
          end
        end)

      assert Enum.any?(mob.internal.events, &(is_struct(&1, Effects.MonsterTalk) and &1.text == "Home again."))
      assert mob.movement_block.position == {0.0, 0.0, 0.0, 2.5}
      assert Enum.any?(mob.internal.events, &match?(%Effects.SetFacing{facing: {:angle, 2.5}}, &1))
    end
  end

  describe "drop_threat/2" do
    test "pets keep their auras and health when the final opponent leaves combat" do
      target = player_guid()
      mob = fixture_mob(position: {20.0, 0.0, 0.0, 0.0}, spline_nodes: [])

      holders = [
        %Holder{
          spell: %Spell{id: 10, attributes: MapSet.new([:passive])},
          caster_guid: mob.object.guid,
          expires_at: -1
        },
        %Holder{spell: %Spell{id: 11}, caster_guid: target, expires_at: 10_000, negative?: true}
      ]

      for command <- [:attack, :follow, :stay] do
        unit = %{mob.unit | target: target, health: 40, max_health: 100, auras: holders}

        internal = %{
          mob.internal
          | in_combat: true,
            threat: %{target => 100.0},
            pet: %Pet{
              owner_guid: 1,
              kind: :hunter_pet,
              command_state: if(command == :stay, do: :stay, else: :follow),
              attack_command?: command == :attack
            },
            spawn: %Spawn{position: {0.0, 0.0, 0.0}},
            blackboard: %Blackboard{combat: %Blackboard.Combat{auto_attacking: true}}
        }

        pet = drop_threat(%{mob | unit: unit, internal: internal}, target, Context.new(1_000))

        refute pet.internal.in_combat
        assert Threat.entries(pet) == []
        assert pet.unit.target == 0
        assert pet.unit.health == 40
        assert pet.unit.auras == holders
        assert pet.internal.pet.command_state == if(command == :attack, do: :follow, else: command)
        refute pet.internal.pet.attack_command?
        assert pet.internal.blackboard.pet.returning == :combat
        refute pet.internal.blackboard.navigation.returning_home?
        assert pet.internal.navigation_intents == []
        assert pet.movement_block.position == mob.movement_block.position
        assert Enum.any?(pet.internal.events, &is_struct(&1, Effects.AttackStop))
      end
    end

    test "fully leaves combat when vanish removes the last hostile reference" do
      target = Guid.from_low_guid(:player, 50)

      mob = %Mob{
        object: %Object{guid: mob_guid(50)},
        unit: %Unit{target: target, flags: 0x00080000, dynamic_flags: 0, auras: []},
        internal: %Internal{
          in_combat: true,
          threat: %{target => 100.0},
          blackboard: %Blackboard{
            combat: %Blackboard.Combat{auto_attacking: true, attack_started: true}
          }
        }
      }

      mob = drop_threat(mob, target)

      refute mob.internal.in_combat
      assert Threat.entries(mob) == []
      assert mob.unit.target == 0
      refute mob.internal.blackboard.combat.auto_attacking
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.AttackStop))
    end

    test "restores spawn orientation after the last hostile reference is removed at home" do
      target = player_guid()

      mob =
        fixture_mob(position: {0.0, 0.0, 0.0, 1.0})
        |> BT.init(MobBT.tree())

      unit = %{mob.unit | target: target, health: 40, max_health: 100, auras: []}

      internal = %{
        mob.internal
        | in_combat: true,
          threat: %{target => 100.0},
          spawn: %Spawn{
            movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 2.5}},
            position: {0.0, 0.0, 0.0}
          },
          blackboard: %Blackboard{combat: %Blackboard.Combat{auto_attacking: true}}
      }

      mob = drop_threat(%{mob | unit: unit, internal: internal}, target)
      {_status, mob} = BehaviorRunner.tick(mob.internal.behavior_tree, mob, AIEnvironment.context(mob, Time.now()))

      assert mob.movement_block.position == {0.0, 0.0, 0.0, 2.5}
      assert Enum.any?(mob.internal.events, &match?(%Effects.SetFacing{facing: {:angle, 2.5}}, &1))
    end

    @tag :namigator_maps
    test "evades to its spawn after vanish removes the last hostile reference" do
      target = player_guid()
      spawn = {0.0, 0.0, 0.0}
      mob = fixture_mob(position: {20.0, 0.0, 0.0, 0.0})
      unit = %{mob.unit | target: target, health: 40, max_health: 100, auras: []}

      internal = %{
        mob.internal
        | in_combat: true,
          running: true,
          threat: %{target => 100.0},
          spawn: %Spawn{position: spawn},
          blackboard: %Blackboard{combat: %Blackboard.Combat{auto_attacking: true}}
      }

      mob =
        %{mob | unit: unit, internal: internal}
        |> drop_threat(target)
        |> NavigationResolver.resolve(Time.now())

      refute mob.internal.in_combat
      assert mob.unit.health == 100
      assert mob.internal.blackboard.navigation.move_target == spawn
      assert Movement.moving?(mob, Time.now())
    end

    test "reselects from the remaining threat table when the current victim vanishes" do
      vanished = player_guid()
      replacement = player_guid()
      mob = fixture_mob(level: 5, faction_template: 17)
      unit = %{mob.unit | target: vanished}
      internal = %{mob.internal | in_combat: true, threat: %{vanished => 100.0, replacement => 50.0}}
      mob = %{mob | unit: unit, internal: internal}

      put_spatial_target(:players, replacement, {1.0, 0.0, 0.0}, alliance(), 5)

      mob = drop_threat(mob, vanished)

      assert mob.internal.in_combat
      assert mob.unit.target == replacement
      refute Threat.tracking?(mob, vanished)
    end

    test "does nothing when a nearby living mob never tracked the vanished player" do
      target = player_guid()
      mob = fixture_mob(position: {20.0, 0.0, 0.0, 0.0})
      unit = %{mob.unit | health: 40, max_health: 100, auras: []}
      internal = %{mob.internal | threat: %{}, spawn: %Spawn{position: {0.0, 0.0, 0.0}}}
      mob = %{mob | unit: unit, internal: internal}

      assert drop_threat(mob, target) == mob
    end

    test "does not evade, heal, or clear loot from a corpse" do
      target = player_guid()
      tap = %{player: target, group_id: nil}
      mob = fixture_mob(position: {20.0, 0.0, 0.0, 0.0}, spline_nodes: [])

      unit = %{
        mob.unit
        | health: 0,
          max_health: 100,
          target: 0,
          dynamic_flags: 0x0005,
          auras: []
      }

      internal = %{
        mob.internal
        | in_combat: false,
          threat: %{},
          spawn: %Spawn{position: {0.0, 0.0, 0.0}},
          loot: %Loot{tapped_by: tap},
          death_finalized?: true
      }

      corpse = %{mob | unit: unit, internal: internal}

      assert drop_threat(corpse, target) == corpse
    end

    test "only releases a stale threat reference from a corpse" do
      target = player_guid()
      tap = %{player: target, group_id: nil}
      mob = fixture_mob(position: {20.0, 0.0, 0.0, 0.0}, spline_nodes: [])
      unit = %{mob.unit | health: 0, max_health: 100, target: 0, dynamic_flags: 0x0005, auras: []}

      internal = %{
        mob.internal
        | in_combat: false,
          threat: %{target => 100.0},
          spawn: %Spawn{position: {0.0, 0.0, 0.0}},
          loot: %Loot{tapped_by: tap},
          death_finalized?: true
      }

      corpse = %{mob | unit: unit, internal: internal}
      result = drop_threat(corpse, target)

      assert result.unit == corpse.unit
      assert result.internal.loot == corpse.internal.loot
      assert result.internal.threat == %{}
      assert [%Effects.ThreatRefLost{target_guid: ^target}] = result.internal.events
    end
  end

  describe "tree/0" do
    test "leaves combat when the final victim disappears from the world" do
      target = player_guid()
      mob = fixture_mob()

      mob =
        %{
          mob
          | unit: %{mob.unit | target: target, health: 100, max_health: 100, auras: []},
            internal: %{
              mob.internal
              | in_combat: true,
                threat: %{target => 100.0},
                blackboard: %Blackboard{
                  combat: %Blackboard.Combat{auto_attacking: true, attack_started: true}
                }
            }
        }
        |> BT.init(MobBT.tree())

      {_status, mob} = BehaviorRunner.tick(mob.internal.behavior_tree, mob, AIEnvironment.context(mob, 1_000))
      mob = NavigationResolver.resolve(mob, 1_000)

      refute mob.internal.in_combat
      assert mob.internal.threat == %{}
      assert mob.unit.target == 0
      refute mob.internal.blackboard.combat.auto_attacking
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.AttackStop))
    end

    test "leaves combat when it entered with nobody left to fight" do
      mob = fixture_mob()

      mob =
        %{
          mob
          | unit: %{mob.unit | health: 100, max_health: 100, auras: []},
            internal: %{
              mob.internal
              | in_combat: true,
                threat: %{},
                blackboard: Blackboard.new(),
                spawn: %Spawn{position: {5.0, 0.0, 0.0}}
            }
        }
        |> BT.init(MobBT.tree())

      {_status, mob} = BehaviorRunner.tick(mob.internal.behavior_tree, mob, AIEnvironment.context(mob, 1_000))

      refute mob.internal.in_combat
      assert mob.internal.blackboard.navigation.returning_home?
    end

    test "interrupts a wander spline when combat begins" do
      now = Time.now()

      state =
        fixture_mob(
          start_time: now,
          duration: 10_000,
          spline_nodes: [{1.0, 0.0, 0.0}]
        )

      state = %{
        state
        | unit: %{
            state.unit
            | health: 100,
              max_health: 100,
              min_damage: 3,
              max_damage: 3,
              base_attack_time: 2_000
          },
          internal: %{state.internal | in_combat: true}
      }

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{
          target: {1.0, 0.0, 0.0},
          move_target: {1.0, 0.0, 0.0}
        }
      }

      {:success, state, blackboard} = MobBT.interrupt_idle_movement(state, blackboard, now)

      assert state.movement_block.spline_nodes == []
      assert blackboard.navigation.move_target == nil
      assert Enum.any?(state.internal.events, &match?(%Effects.MovementStopped{}, &1))
    end

    test "a stunned creature keeps running its combat timers" do
      victim = player_guid()
      talk = %ScriptStep{command: :talk, texts: [%{text: "Help!", chat_type: :say, language: 0, emote_id: 0}]}
      event = %AIEvent{id: 1, event_type: :timer_in_combat, chance: 100, actions: [[talk]]}
      stun = %Holder{spell: %Spell{id: 12}, auras: [%Aura{type: :mod_stun}]}
      mob = fixture_mob()

      mob =
        %{
          mob
          | unit: %{mob.unit | target: victim, health: 100, max_health: 100, auras: [stun]},
            internal: %{
              mob.internal
              | in_combat: true,
                threat: %{victim => 100.0},
                creature: %Creature{ai_events: [event]}
            }
        }
        |> BT.init(MobBT.tree())

      assert {{:running, _delay, :stunned}, mob} =
               BehaviorRunner.tick(mob.internal.behavior_tree, mob, AIEnvironment.context(mob, 1_000))

      assert [%Effects.MonsterTalk{}] = Enum.filter(mob.internal.events, &is_struct(&1, Effects.MonsterTalk))
    end

    test "an idle creature with nothing scheduled sleeps until a message arrives" do
      mob = fixture_mob()
      mob = %{mob | unit: %{mob.unit | health: 100, max_health: 100, auras: []}} |> BT.init(MobBT.tree())

      assert {{:running, :infinity, :idle}, mob} =
               BehaviorRunner.tick(mob.internal.behavior_tree, mob, AIEnvironment.context(mob, 1_000))

      refute Blackboard.aggro_check?(mob.internal.blackboard)

      assert {{:running, :infinity, :idle}, _mob} =
               BehaviorRunner.tick(mob.internal.behavior_tree, mob, AIEnvironment.context(mob, 60_000))
    end
  end

  describe "wait_until_wander_ready/3" do
    test "returns a running delay from explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{navigation: %Blackboard.Navigation{next_wander_at: 1_250}}

      assert {{:running, 250, :wander}, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end

    test "succeeds when ready at explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{navigation: %Blackboard.Navigation{next_wander_at: 1_000}}

      assert {:success, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end

    test "waits out a long wander without polling for aggro" do
      state = fixture_mob()
      blackboard = %Blackboard{navigation: %Blackboard.Navigation{next_wander_at: 5_000}}

      assert {{:running, 4_000, :wander}, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end
  end

  describe "wait_until_waypoint_ready/3" do
    test "returns a running delay from explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{navigation: %Blackboard.Navigation{next_waypoint_at: 1_250}}

      assert {{:running, 250, :waypoint}, ^state, ^blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, 1_000)
    end

    test "waits out a long waypoint pause without polling for aggro" do
      state = fixture_mob()
      blackboard = %Blackboard{navigation: %Blackboard.Navigation{next_waypoint_at: 5_000}}

      assert {{:running, 4_000, :waypoint}, ^state, ^blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, 1_000)
    end

    test "holds until the creature's summons are gone, then runs the release steps" do
      summon = Guid.from_low_guid(:mob, 9522, Unique.integer())
      release = [%ScriptStep{command: :set_run, datalong: 1}]
      blackboard = WaypointHold.start(%Blackboard{}, 1_000, 400_000, release)
      state = WaypointHold.track(fixture_mob(), summon)

      assert {{:running, 1, :waypoint}, _state, _blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, Context.new(1_000))

      assert {{:running, 399_000, :waypoint}, _state, _blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, Context.new(2_000))

      ended = %SummonEvent{event: :summoned_just_died, entry: 9522, world: nil, observation: %{guid: summon}}
      state = WaypointHold.forget(state, ended)

      assert {:success, _state, released} = MobBT.wait_until_waypoint_ready(state, blackboard, Context.new(2_000))
      assert released.navigation.waypoint_hold == nil
      assert released.navigation.run_mode
    end

    test "ignores the summons that were already alive when the hold began" do
      companion = Guid.from_low_guid(:mob, 11_564, Unique.integer())
      state = WaypointHold.track(fixture_mob(), companion)

      blackboard =
        WaypointHold.start(%Blackboard{}, 1_000, 400_000, [], earlier_summons: state.internal.live_summons)

      assert {:success, _state, %Blackboard{navigation: %{waypoint_hold: nil}}} =
               MobBT.wait_until_waypoint_ready(state, blackboard, Context.new(2_000))

      ambusher = Guid.from_low_guid(:mob, 4_677, Unique.integer())
      blackboard = WaypointHold.start(%Blackboard{}, 1_000, 400_000, [], earlier_summons: state.internal.live_summons)
      state = WaypointHold.track(state, ambusher)

      assert {{:running, 399_000, :waypoint}, _state, _blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, Context.new(2_000))
    end

    test "holds a signal hold until it is released" do
      release = [%ScriptStep{command: :set_run, datalong: 1}]
      blackboard = WaypointHold.start(%Blackboard{}, 1_000, 600_000, release, mode: :signal)
      state = fixture_mob()

      assert {{:running, 599_000, :waypoint}, _state, _blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, Context.new(2_000))

      blackboard = WaypointHold.release(blackboard, 3_000)

      assert {:success, _state, released} = MobBT.wait_until_waypoint_ready(state, blackboard, Context.new(3_000))
      assert released.navigation.waypoint_hold == nil
      assert released.navigation.run_mode
    end

    test "runs a signal hold's expired steps only when nothing released it" do
      release = [%ScriptStep{command: :set_run, datalong: 1}]
      expired = [%ScriptStep{command: :set_run, datalong: 0}]
      state = fixture_mob()
      run_mode = fn blackboard -> blackboard.navigation.run_mode end

      held =
        %Blackboard{navigation: %{%Blackboard{}.navigation | run_mode: true}}
        |> WaypointHold.start(1_000, 5_000, release, mode: :signal, expired_steps: expired)

      assert {:success, _state, timed_out} = MobBT.wait_until_waypoint_ready(state, held, Context.new(6_000))
      refute run_mode.(timed_out)

      signaled = WaypointHold.release(held, 3_000)
      assert {:success, _state, released} = MobBT.wait_until_waypoint_ready(state, signaled, Context.new(6_000))
      assert run_mode.(released)
    end

    test "gives up holding once the hold runs out" do
      state = WaypointHold.track(fixture_mob(), Guid.from_low_guid(:mob, 9522, Unique.integer()))
      blackboard = WaypointHold.start(%Blackboard{}, 1_000, 5_000, [])

      assert {:success, _state, %Blackboard{navigation: %{waypoint_hold: nil}}} =
               MobBT.wait_until_waypoint_ready(state, blackboard, Context.new(6_000))
    end
  end

  describe "scripted waypoint routes" do
    test "special paths retain authored heights without ground pathfinding" do
      destination = {10.0, 0.0, 40.0}

      route = %WaypointRoute{
        first_point: 1,
        destination_point: 1,
        points: %{1 => %Waypoint{position: {10.0, 0.0, 40.0, nil}, wait_time: 0}},
        repeat?: false,
        pathfind?: false
      }

      blackboard = %Blackboard{navigation: %Blackboard.Navigation{scripted_waypoint_route: route}}
      state = fixture_mob(spline_nodes: []) |> BT.init(MobBT.tree(), blackboard)
      {_, requested} = BehaviorRunner.tick(MobBT.tree(), state, Context.new(1_000))
      moved = NavigationResolver.resolve(requested, 1_000, fn _, _, _, _ -> flunk("special route pathfinding") end)
      assert moved.movement_block.spline_nodes == [destination]

      arrived = Movement.sync_position(moved, 100_000)
      {_, finished} = BehaviorRunner.tick(MobBT.tree(), arrived, Context.new(100_000))
      assert %Effects.MovementInform{motion_type: 2, point_id: 1} in finished.internal.events
      assert finished.internal.blackboard.navigation.scripted_waypoint_route.destination_point == nil

      home = %{blackboard | navigation: %{blackboard.navigation | returning_home?: true, target: destination}}
      {:success, requested, _} = MobBT.move_to_target(state, home, Context.new(1_000))

      NavigationResolver.resolve(requested, 1_000, fn _, _, _, _ ->
        send(self(), :home_pathfinding)
        nil
      end)

      assert_received :home_pathfinding
    end

    test "evading walkers return to the last point they reached instead of their spawn" do
      points = %{
        1 => %Waypoint{position: {5.0, 0.0, 0.0, nil}},
        2 => %Waypoint{position: {10.0, 0.0, 0.0, nil}},
        3 => %Waypoint{position: {15.0, 0.0, 0.0, nil}}
      }

      reached = %WaypointRoute{first_point: 1, destination_point: 3, last_point: 2, points: points}
      fresh = %{reached | destination_point: 1, last_point: nil}

      for {scripted, spawned, home} <- [
            {reached, nil, {10.0, 0.0, 0.0}},
            {nil, reached, {10.0, 0.0, 0.0}},
            {fresh, nil, {0.0, 0.0, 0.0}}
          ] do
        mob = fixture_mob(position: {30.0, 0.0, 0.0, 0.0}, spline_nodes: [])
        blackboard = %Blackboard{navigation: %Blackboard.Navigation{scripted_waypoint_route: scripted}}
        spawn = %Spawn{position: {0.0, 0.0, 0.0}, waypoint_route: spawned}
        mob = %{mob | internal: %{mob.internal | spawn: spawn, blackboard: blackboard}}
        %{entity: mob} = Engagement.enter(mob, player_guid(), 0, selection: :target)

        navigation = MobBT.reset_after_combat(mob, Context.new(1_000)).internal.blackboard.navigation
        assert navigation.returning_home?
        assert navigation.move_target == home
      end
    end

    test "an evading creature heals only if it regenerates" do
      for {regenerate_stats, health} <- [{0x3, 100}, {0x0, 40}] do
        mob = fixture_mob(position: {0.0, 0.0, 0.0, 0.0}, spline_nodes: [])
        creature = %{mob.internal.creature | regenerate_stats: regenerate_stats}

        mob = %{
          mob
          | unit: %{mob.unit | health: 40, max_health: 100},
            internal: %{mob.internal | creature: creature, spawn: %Spawn{position: {0.0, 0.0, 0.0}}}
        }

        %{entity: mob} = Engagement.enter(mob, player_guid(), 0, selection: :target)

        assert MobBT.reset_after_combat(mob, Context.new(1_000)).unit.health == health
      end
    end

    test "a creature with no path home takes the straight line there" do
      home = {0.0, 0.0, 0.0}
      aloft = fixture_mob(position: {30.0, 0.0, 20.0, 0.0}, spline_nodes: [])
      no_path = fn _map_id, _start, _destination, _opts -> nil end

      for navigation <- [
            %Blackboard.Navigation{returning_home?: true, target: home},
            Blackboard.start_home(Blackboard.new(), home).navigation
          ] do
        {:success, requested, _} = MobBT.move_to_target(aloft, %Blackboard{navigation: navigation}, Context.new(1_000))
        assert NavigationResolver.resolve(requested, 1_000, no_path).movement_block.spline_nodes == [home]
      end

      wandering = %Blackboard{navigation: %Blackboard.Navigation{target: {10.0, 0.0, 0.0}}}
      {:success, requested, _} = MobBT.move_to_target(aloft, wandering, Context.new(1_000))
      assert NavigationResolver.resolve(requested, 1_000, no_path).movement_block.spline_nodes == []
    end

    test "arrival reports the original point once and failed paths cannot advance it" do
      route = %WaypointRoute{
        first_point: 37,
        destination_point: 37,
        points: %{37 => %Waypoint{position: {10.0, 0.0, 0.0, nil}, wait_time: 0}},
        repeat?: false
      }

      blackboard = %Blackboard{navigation: %Blackboard.Navigation{scripted_waypoint_route: route}}
      state = fixture_mob(spline_nodes: []) |> BT.init(MobBT.tree(), blackboard)
      {_, requested} = BehaviorRunner.tick(MobBT.tree(), state, Context.new(1_000))
      failed = NavigationResolver.resolve(requested, 1_000, fn _, _, _, _ -> nil end)
      {{:running, _, :blocked}, failed} = BehaviorRunner.tick(MobBT.tree(), failed, Context.new(1_001))
      assert failed.internal.blackboard.navigation.scripted_waypoint_route.destination_point == 37
      refute Enum.any?(failed.internal.events, &is_struct(&1, Effects.MovementInform))

      moving = NavigationResolver.resolve(requested, 1_000, fn _, _, to, _ -> [to] end)
      arrived = Movement.sync_position(moving, 5_000)
      {_, finished} = BehaviorRunner.tick(MobBT.tree(), arrived, Context.new(5_000))
      assert %Effects.MovementInform{motion_type: 2, point_id: 37} in finished.internal.events
      assert finished.internal.blackboard.navigation.scripted_waypoint_route.destination_point == nil
      {_, later} = BehaviorRunner.tick(MobBT.tree(), finished, Context.new(6_000))
      assert Enum.count(later.internal.events, &is_struct(&1, Effects.MovementInform)) == 1
    end

    test "a point movement suspends idle waypoint navigation until arrival" do
      route = %WaypointRoute{destination_point: 1, points: %{1 => %Waypoint{position: {20.0, 0.0, 0.0, nil}}}}
      blackboard = %Blackboard{navigation: %Blackboard.Navigation{scripted_waypoint_route: route}}
      event = %Effects.MovementInform{motion_type: 9, point_id: 1}
      state = fixture_mob(spline_nodes: []) |> BT.init(MobBT.tree(), blackboard)
      moving = Movement.move_along_path(state, [{10.0, 0.0, 0.0}], [velocity: 10.0, movement_inform: event], 0)
      {{:running, _, :movement}, ticked} = BehaviorRunner.tick(MobBT.tree(), moving, Context.new(500))
      assert ticked.internal.navigation_intents == []
      assert ticked.internal.movement_options[:movement_inform] == event
    end

    test "the behavior tree prioritizes the runtime route over spawn movement" do
      route = %WaypointRoute{
        first_point: 1,
        destination_point: 1,
        points: %{1 => %Waypoint{position: {10.0, 0.0, 0.0, nil}, wait_time: 0}},
        repeat?: false
      }

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{scripted_waypoint_route: route}
      }

      state =
        fixture_mob(spline_nodes: [])
        |> BT.init(MobBT.tree(), blackboard)

      assert {{:running, 0, :navigation}, state} =
               BehaviorRunner.tick(MobBT.tree(), state, AIEnvironment.context(state, 1_000))

      state = NavigationResolver.resolve(state, 1_000, fn _map, _from, to, _opts -> [to] end)

      assert state.movement_block.spline_nodes == [{10.0, 0.0, 0.0}]
      assert state.internal.blackboard.navigation.move_target == {10.0, 0.0, 0.0}
    end

    test "the behavior tree uses a runtime random movement anchor" do
      anchor = {5.0, 6.0, 7.0}
      destination = {8.0, 9.0, 10.0}
      blackboard = Blackboard.start_wander(Blackboard.new(), anchor, 12.0)

      state =
        fixture_mob(spline_nodes: [])
        |> BT.init(MobBT.tree(), blackboard)

      context =
        Context.new(1_000,
          navigation: NavigationContext.new(%{{0, anchor, 12.0} => destination})
        )

      assert {{:running, 0, :navigation}, state} =
               BehaviorRunner.tick(MobBT.tree(), state, context)

      state = NavigationResolver.resolve(state, 1_000, fn _map, _from, to, _opts -> [to] end)

      assert state.movement_block.spline_nodes == [destination]
      assert state.internal.blackboard.navigation.move_target == destination
    end

    test "home movement restores the spawn movement policy after arrival" do
      home = {10.0, 0.0, 0.0}
      spawn = %Spawn{position: home, movement_type: 1, distance: 5.0}
      blackboard = Blackboard.start_home(Blackboard.new(), home)

      state =
        fixture_mob(spline_nodes: [])
        |> then(&%{&1 | internal: %{&1.internal | spawn: spawn}})
        |> BT.init(MobBT.tree(), blackboard)

      assert {{:running, 0, :navigation}, state} =
               BehaviorRunner.tick(MobBT.tree(), state, Context.new(1_000))

      state =
        state
        |> NavigationResolver.resolve(1_000, fn _map, _from, to, _opts -> [to] end)
        |> finish_current_move()

      {:success, state} =
        BehaviorRunner.tick(MobBT.tree(), state, Context.new(1_000))

      assert state.internal.blackboard.navigation.movement_override == nil
      assert state.internal.blackboard.navigation.target == nil
    end

    test "scripted home movement fires reached_home on arrival" do
      home = {10.0, 0.0, 0.0}
      talk = %ScriptStep{command: :talk, texts: [%{text: "Back.", chat_type: :say, language: 0, emote_id: 0}]}
      event = %AIEvent{id: 1, event_type: :reached_home, chance: 100, actions: [[talk]]}

      state =
        fixture_mob(spline_nodes: [])
        |> then(fn mob ->
          internal = mob.internal
          %{mob | internal: %{internal | spawn: %Spawn{position: home}, creature: %Creature{ai_events: [event]}}}
        end)
        |> BT.init(MobBT.tree(), Blackboard.start_home(Blackboard.new(), home))

      {_status, state} = BehaviorRunner.tick(MobBT.tree(), state, Context.new(1_000))
      refute Enum.any?(state.internal.events, &is_struct(&1, Effects.MonsterTalk))

      state =
        state
        |> NavigationResolver.resolve(1_000, fn _map, _from, to, _opts -> [to] end)
        |> finish_current_move()

      {:success, state} = BehaviorRunner.tick(MobBT.tree(), state, Context.new(1_000))
      assert Enum.any?(state.internal.events, &match?(%Effects.MonsterTalk{text: "Back."}, &1))
    end
  end

  describe "wait_for_chase_tick/3" do
    test "disabled combat movement retains the normal chase wake on a negative clock" do
      state = fixture_mob(spline_nodes: [])
      blackboard = Blackboard.set_combat_movement(Blackboard.new(), false)
      assert {{:running, 1_000, :chase}, ^state, ^blackboard} = MobBT.wait_for_chase_tick(state, blackboard, -10_000)
    end

    test "returns delay until the next chase check" do
      state = fixture_mob()
      blackboard = %Blackboard{navigation: %Blackboard.Navigation{next_chase_at: 1_250}}

      assert {{:running, 250, :chase}, ^state, ^blackboard} =
               MobBT.wait_for_chase_tick(state, blackboard, 1_000)
    end
  end

  describe "interrupt_idle_movement/3" do
    test "halts a wander spline when combat starts within melee range" do
      state =
        fixture_mob(
          start_time: 0,
          duration: 10_000,
          spline_nodes: [{100.0, 0.0, 0.0}]
        )

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{
          target: {100.0, 0.0, 0.0},
          move_target: {100.0, 0.0, 0.0},
          next_chase_at: 5_000
        }
      }

      assert {:success, state, blackboard} = MobBT.interrupt_idle_movement(state, blackboard, 1_000)
      assert state.movement_block.spline_nodes == []
      assert Enum.any?(state.internal.events, &match?(%Effects.MovementStopped{}, &1))
      assert blackboard.navigation.target == nil
      assert blackboard.navigation.move_target == nil
      assert blackboard.navigation.next_chase_at == 0
    end

    test "leaves combat movement untouched" do
      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{100.0, 0.0, 0.0}])

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{last_target_pos: {100.0, 0.0, 0.0}}
      }

      assert {:success, ^state, ^blackboard} = MobBT.interrupt_idle_movement(state, blackboard, 1_000)
    end
  end

  defp contact_context(%Mob{internal: %Internal{world: world}}, target_guid, position) do
    observations =
      case position do
        {x, y, z} -> %{target_guid => %Observation{guid: target_guid, position: {world, x, y, z}}}
        nil -> %{}
      end

    Context.new(2_000, perception: Perception.new(2_000, nil, observations, %{mobs: [], players: [], game_objects: []}))
  end

  describe "chase_repath_distance/2" do
    test "uses combined melee reach and the target's bounding radius" do
      state = fixture_mob()
      expected = (Unit.default_combat_reach() + 4.0 + 1.333) * 0.75 - 1.0

      assert_in_delta MobBT.chase_repath_distance(state, %{combat_reach: 4.0, bounding_radius: 1.0}), expected, 0.0001
    end
  end

  describe "halt_at_contact/3" do
    test "halts, faces the target, and emits a stop when riding a spline into contact" do
      target_guid = player_guid()
      target_position = {4.0, 0.0, 0.0}

      state =
        fixture_mob(
          start_time: 0,
          duration: 10_000,
          position: {2.0, 0.0, 0.0, 1.0},
          movement_start_position: {2.0, 0.0, 0.0},
          spline_nodes: [{2.0, 0.0, 0.0}]
        )

      state = put_in(state.unit.target, target_guid)

      assert {:success, state, %Blackboard{}} =
               MobBT.halt_at_contact(state, %Blackboard{}, contact_context(state, target_guid, target_position))

      assert state.movement_block.spline_nodes == []
      assert state.movement_block.position == {2.0, 0.0, 0.0, 0.0}
      assert is_nil(state.internal.movement_start_time)

      assert [
               %Effects.MovementStopped{},
               %Effects.SetFacing{facing: {:target, ^target_guid}}
             ] = state.internal.events
    end

    test "re-faces a stationary target that crosses through melee range" do
      target_guid = player_guid()
      target_position = {-2.0, 0.0, 0.0}

      state =
        fixture_mob(
          start_time: nil,
          position: {0.0, 0.0, 0.0, 0.0},
          movement_start_position: nil,
          spline_nodes: []
        )

      state = put_in(state.unit.target, target_guid)

      assert {:success, state, %Blackboard{}} =
               MobBT.halt_at_contact(state, %Blackboard{}, contact_context(state, target_guid, target_position))

      {_x, _y, _z, orientation} = state.movement_block.position
      assert_in_delta abs(orientation), :math.pi(), 0.0001
      assert [%Effects.SetFacing{facing: {:target, ^target_guid}}] = state.internal.events
    end

    test "keeps moving outside the contact ring" do
      target_guid = player_guid()
      target_position = {9.0, 0.0, 0.0}

      state =
        fixture_mob(
          start_time: 0,
          duration: 10_000,
          position: {2.0, 0.0, 0.0, 0.0},
          movement_start_position: {2.0, 0.0, 0.0},
          spline_nodes: [{2.0, 0.0, 0.0}]
        )

      state = put_in(state.unit.target, target_guid)

      assert {:success, ^state, %Blackboard{}} =
               MobBT.halt_at_contact(state, %Blackboard{}, contact_context(state, target_guid, target_position))

      assert state.movement_block.spline_nodes == [{2.0, 0.0, 0.0}]
      assert state.internal.events == []
    end

    test "does not interrupt a spread move" do
      target_guid = player_guid()
      target_position = {4.0, 0.0, 0.0}

      state =
        fixture_mob(
          start_time: 0,
          duration: 10_000,
          position: {2.0, 0.0, 0.0, 0.0},
          movement_start_position: {2.0, 0.0, 0.0},
          spline_nodes: [{2.0, 0.0, 0.0}]
        )

      state = put_in(state.unit.target, target_guid)
      blackboard = %Blackboard{combat: %Blackboard.Combat{spreading: true}}

      assert {:success, ^state, ^blackboard} =
               MobBT.halt_at_contact(state, blackboard, contact_context(state, target_guid, target_position))

      assert state.movement_block.spline_nodes == [{2.0, 0.0, 0.0}]
    end

    test "clears the spreading flag once stationary" do
      target_guid = player_guid()
      state = put_in(fixture_mob().unit.target, target_guid)

      assert {:success, ^state, %Blackboard{combat: %Blackboard.Combat{spreading: false}}} =
               MobBT.halt_at_contact(
                 state,
                 %Blackboard{combat: %Blackboard.Combat{spreading: true}},
                 contact_context(state, target_guid, nil)
               )
    end
  end

  describe "melee_escape_distance/3" do
    test "is the remaining distance to the melee reach edge" do
      state = fixture_mob()

      assert_in_delta MobBT.melee_escape_distance(state, %{combat_reach: 1.5}, 4.0), 1.0, 0.0001
    end

    test "floors at a minimum threshold near the reach edge" do
      state = fixture_mob()

      assert MobBT.melee_escape_distance(state, %{}, 4.9) == 0.5
    end
  end

  describe "combat_wait/3" do
    test "paces by the next swing when already stationary in range" do
      state = fixture_mob()

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{chase_started: true, last_target_pos: {1.0, 2.0, 3.0}},
        combat: %Blackboard.Combat{next_attack_at: 1_750}
      }

      assert {{:running, delay, :attack}, ^state,
              %Blackboard{
                navigation: %Blackboard.Navigation{
                  next_chase_at: next_chase_at,
                  chase_started: false
                }
              }} =
               MobBT.combat_wait(state, blackboard, 1_000)

      assert delay == 750
      assert next_chase_at == 1_750
    end

    test "paces by movement boundary before the next swing while still moving" do
      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{250.0, 0.0, 0.0}])

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{chase_started: true, last_target_pos: {1.0, 2.0, 3.0}},
        combat: %Blackboard.Combat{next_attack_at: 5_000}
      }

      assert {{:running, 3_980, :chase}, ^state,
              %Blackboard{
                navigation: %Blackboard.Navigation{next_chase_at: 4_980, chase_started: false}
              }} =
               MobBT.combat_wait(state, blackboard, 1_000)
    end

    test "wakes at the contact ring before the spatial boundary while closing in" do
      target_guid = player_guid()
      SpatialHash.update(:players, target_guid, 0, 50.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{250.0, 0.0, 0.0}])
      state = put_in(state.unit.target, target_guid)
      blackboard = %Blackboard{combat: %Blackboard.Combat{next_attack_at: 5_000}}

      assert {{:running, 880, :chase}, _state, %Blackboard{navigation: %Blackboard.Navigation{next_chase_at: 1_880}}} =
               MobBT.combat_wait(state, blackboard, AIEnvironment.context(state, 1_000))
    end
  end

  describe "wait_for_arrival/3" do
    test "returns remaining movement duration from explicit time" do
      state = fixture_mob(start_time: 900, duration: 500)

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{move_target: {1.0, 2.0, 3.0}}
      }

      assert {{:running, 400, :movement}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "waits until arrival when movement stays in the current spatial cell" do
      state = fixture_mob(start_time: 900, duration: 5_000)

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{move_target: {1.0, 2.0, 3.0}}
      }

      assert {{:running, 4_900, :movement}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "wakes at the next spatial cell boundary before arrival" do
      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{250.0, 0.0, 0.0}])

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{move_target: {250.0, 0.0, 0.0}}
      }

      assert {{:running, 3_980, :movement}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "clears move target after arrival" do
      state = fixture_mob(start_time: 0, duration: 500)

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{
          target: {1.0, 2.0, 3.0},
          move_target: {1.0, 2.0, 3.0}
        }
      }

      assert {:success, ^state, %Blackboard{navigation: %Blackboard.Navigation{target: nil, move_target: nil}}} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end
  end

  describe "move_to_target/3" do
    test "succeeds when already moving to target" do
      state = fixture_mob()

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{
          target: {1.0, 2.0, 3.0},
          move_target: {1.0, 2.0, 3.0}
        }
      }

      assert {:success, ^state, ^blackboard} =
               MobBT.move_to_target(state, blackboard, AIEnvironment.context(state, 1_000))
    end

    test "fails and clears stale move target without a target" do
      state = fixture_mob()

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{move_target: {1.0, 2.0, 3.0}}
      }

      assert {:failure, ^state, %Blackboard{navigation: %Blackboard.Navigation{target: nil, move_target: nil}}} =
               MobBT.move_to_target(state, blackboard, AIEnvironment.context(state, 1_000))
    end
  end

  describe "set_next_waypoint_wait/3" do
    test "schedules from explicit time and clears waypoint state" do
      state = fixture_mob()

      blackboard = %Blackboard{
        navigation: %Blackboard.Navigation{
          target: {1.0, 2.0, 3.0},
          orientation: 1.5,
          wait_time: 250
        }
      }

      assert {:success, ^state,
              %Blackboard{
                navigation: %Blackboard.Navigation{
                  next_waypoint_at: 1_250,
                  target: nil,
                  orientation: nil,
                  wait_time: nil
                }
              }} =
               MobBT.set_next_waypoint_wait(state, blackboard, 1_000)
    end
  end

  describe "try_aggro/3" do
    test "aggros onto the nearest hostile player in range" do
      source_guid = mob_guid(17)
      target_guid = player_guid()
      other_guid = player_guid()

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {10.0, 0.0, 0.0}, alliance(), 5)
      put_spatial_target(:players, other_guid, {12.0, 0.0, 0.0}, alliance(), 5)

      assert {:failure, state, %Blackboard{combat: %Blackboard.Combat{aggro_check?: false}}} =
               MobBT.try_aggro(state, blackboard, AIEnvironment.context(state, 1_000))

      assert state.unit.target == target_guid
      assert state.internal.in_combat == true
      assert state.internal.last_hostile_time == 1_000

      assert [
               %Effects.CombatLeashEvent{event: {:start, 1_000, nil}},
               %Effects.ThreatRefGained{target_guid: ^target_guid},
               %Effects.AttackerGained{target_guid: ^target_guid},
               %Effects.CreatureGroupEvent{event: {:attack, ^target_guid, _leash}}
             ] = state.internal.events

      assert Metadata.query(target_guid, [:attacker_count]) == %{attacker_count: 0}
    end

    test "does not aggro neutral or friendly nearby units" do
      source_guid = mob_guid(17)
      friendly_guid = mob_guid(17)
      neutral_guid = mob_guid(32)

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:mobs, friendly_guid, {10.0, 0.0, 0.0}, defias(), 5)
      put_spatial_target(:mobs, neutral_guid, {8.0, 0.0, 0.0}, wolf(), 5)

      assert {:failure, ^state, %Blackboard{combat: %Blackboard.Combat{aggro_check?: false}}} =
               MobBT.try_aggro(state, blackboard, 1_000)
    end

    test "does not proximity aggro when disabled by creature extra flags" do
      source_guid = mob_guid(17)
      target_guid = player_guid()

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      Metadata.update(source_guid, %{proximity_aggro?: false})
      put_spatial_target(:players, target_guid, {10.0, 0.0, 0.0}, alliance(), 5)

      assert {:failure, ^state, %Blackboard{combat: %Blackboard.Combat{aggro_check?: false}}} =
               MobBT.try_aggro(state, blackboard, AIEnvironment.context(state, 1_000))
    end

    test "uses level-adjusted aggro range" do
      source_guid = mob_guid(17)
      target_guid = player_guid()

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {6.0, 0.0, 0.0}, alliance(), 30)

      assert {:failure, ^state, %Blackboard{combat: %Blackboard.Combat{aggro_check?: false}}} =
               MobBT.try_aggro(state, blackboard, 1_000)
    end

    test "uses the creature detection range for aggro distance" do
      source_guid = mob_guid(17)
      target_guid = player_guid()

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17, detection_range: 10.0)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {12.0, 0.0, 0.0}, alliance(), 5)

      assert {:failure, ^state, %Blackboard{combat: %Blackboard.Combat{aggro_check?: false}}} =
               MobBT.try_aggro(state, blackboard, 1_000)

      assert state.unit.target == 0
    end

    test "does not acquire a stealthed player outside detection distance" do
      source_guid = mob_guid(17)
      target_guid = player_guid()
      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {5.0, 0.0, 0.0}, alliance(), 5)
      Metadata.update(target_guid, %{stealthed?: true, stealth_skill: 25})

      assert {:failure, state, %Blackboard{combat: %Blackboard.Combat{aggro_check?: false}}} =
               MobBT.try_aggro(state, %Blackboard{}, AIEnvironment.context(state, 1_000))

      assert state.unit.target == 0
    end

    test "detection auras reveal nearby stealth only in the creature's facing arc" do
      source_guid = mob_guid(17)
      target_guid = player_guid()
      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)

      aura = %Holder{
        auras: [%Aura{type: :mod_stealth_detect, misc_value: 0, amount: 30}]
      }

      state = %{state | unit: %{state.unit | auras: [aura]}}
      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {5.0, 0.0, 0.0}, alliance(), 5)
      Metadata.update(target_guid, %{stealthed?: true, stealth_skill: 25})

      assert {:failure, detected, _blackboard} =
               MobBT.try_aggro(state, %Blackboard{}, AIEnvironment.context(state, 1_000))

      assert detected.unit.target == target_guid

      state = %{state | movement_block: %{state.movement_block | position: {0.0, 0.0, 0.0, :math.pi()}}}

      assert {:failure, undetected, _blackboard} =
               MobBT.try_aggro(state, %Blackboard{}, AIEnvironment.context(state, 1_000))

      assert undetected.unit.target == 0
    end
  end

  describe "aggro_radius_for/4" do
    test "uses the creature detection range as the base radius" do
      assert MobBT.aggro_radius_for(18.0, 10, 10) == 18.0
    end

    test "shrinks against higher-level targets and grows against lower-level ones" do
      assert MobBT.aggro_radius_for(18.0, 10, 15) == 13.0
      assert MobBT.aggro_radius_for(18.0, 40, 20) == 38.0
    end

    test "caps the low-level bonus at 25 levels" do
      assert MobBT.aggro_radius_for(18.0, 60, 1) == 43.0
    end

    test "clamps to the minimum radius" do
      assert MobBT.aggro_radius_for(18.0, 5, 40) == 5.0
      assert MobBT.aggro_radius_for(4.0, 5, 40) == 4.0
    end

    test "never aggros when the detection range is under a yard" do
      assert MobBT.aggro_radius_for(0.0, 10, 10) == 0.0
    end
  end

  describe "maybe_spread/3" do
    test "skips while the mob is still moving" do
      target_guid = player_guid()
      state = put_in(fixture_mob(start_time: 0, duration: 5_000).unit.target, target_guid)
      blackboard = %Blackboard{combat: %Blackboard.Combat{next_spread_at: 0}}

      assert {:success, ^state, ^blackboard} =
               MobBT.maybe_spread(state, blackboard, AIEnvironment.context(state, 1_000))
    end

    test "waits for the spread timer" do
      target_guid = player_guid()
      state = put_in(fixture_mob().unit.target, target_guid)
      blackboard = %Blackboard{combat: %Blackboard.Combat{next_spread_at: 5_000}}

      assert {:success, ^state, ^blackboard} =
               MobBT.maybe_spread(state, blackboard, AIEnvironment.context(state, 1_000))
    end

    test "resets the spread budget when the target is moving" do
      target_guid = player_guid()

      SpatialHash.put_projection(target_guid, %Spline{
        world: WorldRef.open(0),
        origin: {0.0, 0.0, 0.0},
        nodes: [{10.0, 0.0, 0.0}],
        started_at: 0,
        duration_ms: 10_000
      })

      on_exit(fn -> SpatialHash.clear_projection(target_guid) end)

      state = put_in(fixture_mob().unit.target, target_guid)

      blackboard = %Blackboard{
        combat: %Blackboard.Combat{next_spread_at: 0, spread_attempts: 2}
      }

      assert {:success, ^state,
              %Blackboard{
                combat: %Blackboard.Combat{spread_attempts: 0, next_spread_at: next}
              }} =
               MobBT.maybe_spread(state, blackboard, AIEnvironment.context(state, 1_000))

      assert next >= 3_500 and next <= 4_500
    end

    test "stops nudging after the attempt cap" do
      target_guid = player_guid()
      state = put_in(fixture_mob().unit.target, target_guid)

      blackboard = %Blackboard{
        combat: %Blackboard.Combat{next_spread_at: 0, spread_attempts: 3}
      }

      assert {:success, ^state, %Blackboard{combat: %Blackboard.Combat{spread_attempts: 3}}} =
               MobBT.maybe_spread(state, blackboard, AIEnvironment.context(state, 1_000))
    end

    test "does nothing without a stacked neighbor" do
      target_guid = player_guid()
      state = put_in(fixture_mob().unit.target, target_guid)

      blackboard = %Blackboard{
        combat: %Blackboard.Combat{next_spread_at: 0, spread_attempts: 0}
      }

      assert {:success, ^state,
              %Blackboard{
                combat: %Blackboard.Combat{spread_attempts: 0, next_spread_at: next}
              }} =
               MobBT.maybe_spread(state, blackboard, AIEnvironment.context(state, 1_000))

      assert next >= 3_500 and next <= 4_500
    end
  end

  defp finish_current_move(%Mob{internal: %Internal{movement_start_time: start_time} = internal} = mob)
       when is_integer(start_time) do
    duration = mob.movement_block.duration || 0
    %{mob | internal: %{internal | movement_start_time: start_time - duration - 1}}
  end

  defp finish_current_move(%Mob{} = mob), do: mob

  defp drop_threat(mob, target, context \\ Context.new(Time.now())),
    do: MobBT.drop_threat(mob, target, context, ThreatSelection.opts(mob))

  defp fixture_mob(opts \\ []) do
    %Mob{
      object: %Object{
        guid: Keyword.get(opts, :guid, mob_guid(1))
      },
      unit: %Unit{
        level: Keyword.get(opts, :level, 1),
        health: 100,
        faction_template: Keyword.get(opts, :faction_template, 17),
        flags: 0,
        target: 0
      },
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        in_combat: false,
        movement_start_time: Keyword.get(opts, :start_time),
        movement_start_position: Keyword.get(opts, :movement_start_position, {0.0, 0.0, 0.0}),
        creature: %Creature{detection_range: Keyword.get(opts, :detection_range)}
      },
      movement_block: %MovementBlock{
        duration: Keyword.get(opts, :duration, 0),
        position: Keyword.get(opts, :position, {0.0, 0.0, 0.0, 0.0}),
        spline_nodes: Keyword.get(opts, :spline_nodes, [{1.0, 0.0, 0.0}]),
        walk_speed: 2.5,
        run_speed: 7.0
      }
    }
  end

  defp put_spatial_target(table, guid, {x, y, z}, faction_template, level) do
    SpatialHash.update(table, guid, 0, x, y, z)
    put_metadata(guid, faction_template, level)

    on_exit(fn ->
      SpatialHash.remove(table, guid)
      Metadata.delete(guid)
    end)
  end

  defp put_metadata(guid, faction_template, level) do
    Metadata.put(guid, %{
      alive?: true,
      faction_template: faction_template,
      unit_flags: 0,
      level: level,
      attacker_count: 0
    })

    on_exit(fn -> Metadata.delete(guid) end)
  end

  defp player_guid do
    Guid.from_low_guid(:player, bounded_unique(0xFFFFFFFF))
  end

  defp mob_guid(entry) do
    Guid.from_low_guid(:mob, entry, bounded_unique(0x00FFFFFF))
  end

  defp bounded_unique(max) do
    rem(Unique.integer(), max) + 1
  end

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp defias do
    %FactionTemplate{
      id: 17,
      faction: 15,
      flags: 1,
      faction_group: 8,
      friend_group: 0,
      enemy_group: 1,
      friends_0: 15
    }
  end

  defp wolf do
    %FactionTemplate{
      id: 32,
      faction: 29,
      flags: 16,
      faction_group: 0,
      friend_group: 0,
      enemy_group: 0,
      enemies_0: 28
    }
  end
end
