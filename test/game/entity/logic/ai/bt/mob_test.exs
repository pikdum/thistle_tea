defmodule ThistleTea.Game.Entity.Logic.AI.BT.MobTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  describe "reached_home" do
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
          map: 0,
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
          {_status, mob} = BT.tick(mob.internal.behavior_tree, mob)

          if Enum.any?(mob.internal.events, &(&1.type == :spell_start)) do
            {:halt, mob}
          else
            {:cont, finish_current_move(mob)}
          end
        end)

      assert Enum.any?(mob.internal.events, &(&1.type == :spell_start and &1.spell_id == 22_766))
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
          map: 0,
          in_combat: true,
          creature: %Creature{ai_events: [event]},
          spawn: %Spawn{position: {0.0, 0.0, 0.0}, movement_type: 1, distance: 5.0},
          spellbook: %{}
        }
      }

      mob = BT.init(mob, MobBT.tree())

      mob =
        Enum.reduce_while(1..10, mob, fn _i, mob ->
          mob = Movement.sync_position(mob, Time.now())
          {_status, mob} = BT.tick(mob.internal.behavior_tree, mob)

          if Enum.any?(mob.internal.events, &(&1.type == :monster_talk)) do
            {:halt, mob}
          else
            {:cont, finish_current_move(mob)}
          end
        end)

      assert Enum.any?(mob.internal.events, &(&1.type == :monster_talk and &1.text == "Home again."))
    end
  end

  describe "tree/0" do
    test "interrupts a wander spline before attacking an in-range target" do
      target_guid = player_guid()
      SpatialHash.clear_movement(target_guid)
      SpatialHash.update(:players, target_guid, 0, 4.0, 0.0, 0.0)

      on_exit(fn ->
        SpatialHash.clear_movement(target_guid)
        SpatialHash.remove(:players, target_guid)
      end)

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
            | target: target_guid,
              health: 100,
              max_health: 100,
              min_damage: 3,
              max_damage: 3,
              base_attack_time: 2_000
          },
          internal: %{state.internal | in_combat: true}
      }

      blackboard = %Blackboard{target: {1.0, 0.0, 0.0}, move_target: {1.0, 0.0, 0.0}}
      state = BT.init(state, MobBT.tree(), blackboard)

      {_status, state} = BT.tick(state.internal.behavior_tree, state)

      assert state.movement_block.spline_nodes == []
      assert state.internal.blackboard.move_target == nil
      assert Enum.any?(state.internal.events, &match?(%Event{type: :movement_stopped}, &1))
    end
  end

  describe "wait_until_wander_ready/3" do
    test "returns a running delay from explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_wander_at: 1_250}

      assert {{:running, 250, :wander}, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end

    test "succeeds when ready at explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_wander_at: 1_000}

      assert {:success, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end

    test "wakes for aggro before a long wander wait" do
      state = fixture_mob()
      blackboard = %Blackboard{next_wander_at: 5_000, next_aggro_at: 1_250}

      assert {{:running, 250, :aggro}, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end
  end

  describe "wait_until_waypoint_ready/3" do
    test "returns a running delay from explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_waypoint_at: 1_250}

      assert {{:running, 250, :waypoint}, ^state, ^blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, 1_000)
    end

    test "wakes for aggro before a long waypoint wait" do
      state = fixture_mob()
      blackboard = %Blackboard{next_waypoint_at: 5_000, next_aggro_at: 1_250}

      assert {{:running, 250, :aggro}, ^state, ^blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, 1_000)
    end
  end

  describe "wait_for_chase_tick/3" do
    test "returns delay until the next chase check" do
      state = fixture_mob()
      blackboard = %Blackboard{next_chase_at: 1_250}

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
        target: {100.0, 0.0, 0.0},
        move_target: {100.0, 0.0, 0.0},
        next_chase_at: 5_000
      }

      assert {:success, state, blackboard} = MobBT.interrupt_idle_movement(state, blackboard, 1_000)
      assert state.movement_block.spline_nodes == []
      assert Enum.any?(state.internal.events, &match?(%Event{type: :movement_stopped}, &1))
      assert blackboard.target == nil
      assert blackboard.move_target == nil
      assert blackboard.next_chase_at == 0
    end

    test "leaves combat movement untouched" do
      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{100.0, 0.0, 0.0}])
      blackboard = %Blackboard{last_target_pos: {100.0, 0.0, 0.0}}

      assert {:success, ^state, ^blackboard} = MobBT.interrupt_idle_movement(state, blackboard, 1_000)
    end
  end

  describe "chase_repath_distance/2" do
    test "uses combined melee reach and the target's bounding radius" do
      target_guid = player_guid()
      Metadata.put(target_guid, %{combat_reach: 4.0, bounding_radius: 1.0})

      on_exit(fn -> Metadata.delete(target_guid) end)

      state = fixture_mob()
      expected = (Unit.default_combat_reach() + 4.0 + 1.333) * 0.75 - 1.0

      assert_in_delta MobBT.chase_repath_distance(state, target_guid), expected, 0.0001
    end
  end

  describe "halt_at_contact/3" do
    test "halts, faces the target, and emits a stop when riding a spline into contact" do
      target_guid = player_guid()
      SpatialHash.update(:players, target_guid, 0, 4.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      state =
        fixture_mob(
          start_time: 0,
          duration: 10_000,
          position: {2.0, 0.0, 0.0, 1.0},
          movement_start_position: {2.0, 0.0, 0.0},
          spline_nodes: [{2.0, 0.0, 0.0}]
        )

      state = put_in(state.unit.target, target_guid)

      assert {:success, state, %Blackboard{}} = MobBT.halt_at_contact(state, %Blackboard{}, 2_000)
      assert state.movement_block.spline_nodes == []
      assert state.movement_block.position == {2.0, 0.0, 0.0, 0.0}
      assert is_nil(state.internal.movement_start_time)
      assert [%Event{type: :movement_stopped}] = state.internal.events
    end

    test "keeps moving outside the contact ring" do
      target_guid = player_guid()
      SpatialHash.update(:players, target_guid, 0, 9.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      state =
        fixture_mob(
          start_time: 0,
          duration: 10_000,
          position: {2.0, 0.0, 0.0, 0.0},
          movement_start_position: {2.0, 0.0, 0.0},
          spline_nodes: [{2.0, 0.0, 0.0}]
        )

      state = put_in(state.unit.target, target_guid)

      assert {:success, ^state, %Blackboard{}} = MobBT.halt_at_contact(state, %Blackboard{}, 2_000)
      assert state.movement_block.spline_nodes == [{2.0, 0.0, 0.0}]
      assert state.internal.events == []
    end

    test "does not interrupt a spread move" do
      target_guid = player_guid()
      SpatialHash.update(:players, target_guid, 0, 4.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      state =
        fixture_mob(
          start_time: 0,
          duration: 10_000,
          position: {2.0, 0.0, 0.0, 0.0},
          movement_start_position: {2.0, 0.0, 0.0},
          spline_nodes: [{2.0, 0.0, 0.0}]
        )

      state = put_in(state.unit.target, target_guid)
      blackboard = %Blackboard{spreading: true}

      assert {:success, ^state, ^blackboard} = MobBT.halt_at_contact(state, blackboard, 2_000)
      assert state.movement_block.spline_nodes == [{2.0, 0.0, 0.0}]
    end

    test "clears the spreading flag once stationary" do
      target_guid = player_guid()
      state = put_in(fixture_mob().unit.target, target_guid)

      assert {:success, ^state, %Blackboard{spreading: false}} =
               MobBT.halt_at_contact(state, %Blackboard{spreading: true}, 2_000)
    end
  end

  describe "melee_escape_distance/3" do
    test "is the remaining distance to the melee reach edge" do
      target_guid = player_guid()
      Metadata.put(target_guid, %{combat_reach: 1.5})
      on_exit(fn -> Metadata.delete(target_guid) end)

      state = fixture_mob()

      assert_in_delta MobBT.melee_escape_distance(state, target_guid, 4.0), 1.0, 0.0001
    end

    test "floors at a minimum threshold near the reach edge" do
      state = fixture_mob()

      assert MobBT.melee_escape_distance(state, player_guid(), 4.9) == 0.5
    end
  end

  describe "combat_wait/3" do
    test "paces by the next swing when already stationary in range" do
      state = fixture_mob()
      blackboard = %Blackboard{next_attack_at: 1_750, chase_started: true, last_target_pos: {1.0, 2.0, 3.0}}

      assert {{:running, delay, :attack}, ^state, %Blackboard{next_chase_at: next_chase_at, chase_started: false}} =
               MobBT.combat_wait(state, blackboard, 1_000)

      assert delay == 750
      assert next_chase_at == 1_750
    end

    test "paces by movement boundary before the next swing while still moving" do
      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{250.0, 0.0, 0.0}])
      blackboard = %Blackboard{next_attack_at: 5_000, chase_started: true, last_target_pos: {1.0, 2.0, 3.0}}

      assert {{:running, 3_980, :chase}, ^state, %Blackboard{next_chase_at: 4_980, chase_started: false}} =
               MobBT.combat_wait(state, blackboard, 1_000)
    end

    test "wakes at the contact ring before the spatial boundary while closing in" do
      target_guid = player_guid()
      SpatialHash.update(:players, target_guid, 0, 50.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{250.0, 0.0, 0.0}])
      state = put_in(state.unit.target, target_guid)
      blackboard = %Blackboard{next_attack_at: 5_000}

      assert {{:running, 880, :chase}, _state, %Blackboard{next_chase_at: 1_880}} =
               MobBT.combat_wait(state, blackboard, 1_000)
    end
  end

  describe "wait_for_arrival/3" do
    test "returns remaining movement duration from explicit time" do
      state = fixture_mob(start_time: 900, duration: 500)
      blackboard = %Blackboard{move_target: {1.0, 2.0, 3.0}}

      assert {{:running, 400, :movement}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "waits until arrival when movement stays in the current spatial cell" do
      state = fixture_mob(start_time: 900, duration: 5_000)
      blackboard = %Blackboard{move_target: {1.0, 2.0, 3.0}}

      assert {{:running, 4_900, :movement}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "wakes at the next spatial cell boundary before arrival" do
      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{250.0, 0.0, 0.0}])
      blackboard = %Blackboard{move_target: {250.0, 0.0, 0.0}}

      assert {{:running, 3_980, :movement}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "wakes for aggro before the next spatial cell boundary" do
      state = fixture_mob(start_time: 0, duration: 10_000, spline_nodes: [{250.0, 0.0, 0.0}])
      blackboard = %Blackboard{move_target: {250.0, 0.0, 0.0}, next_aggro_at: 1_250}

      assert {{:running, 250, :aggro}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "clears move target after arrival" do
      state = fixture_mob(start_time: 0, duration: 500)
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, move_target: {1.0, 2.0, 3.0}}

      assert {:success, ^state, %Blackboard{target: nil, move_target: nil}} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end
  end

  describe "move_to_target/3" do
    test "succeeds when already moving to target" do
      state = fixture_mob()
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, move_target: {1.0, 2.0, 3.0}}

      assert {:success, ^state, ^blackboard} = MobBT.move_to_target(state, blackboard, 1_000)
    end

    test "fails and clears stale move target without a target" do
      state = fixture_mob()
      blackboard = %Blackboard{move_target: {1.0, 2.0, 3.0}}

      assert {:failure, ^state, %Blackboard{target: nil, move_target: nil}} =
               MobBT.move_to_target(state, blackboard, 1_000)
    end
  end

  describe "set_next_waypoint_wait/3" do
    test "schedules from explicit time and clears waypoint state" do
      state = fixture_mob()
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, orientation: 1.5, wait_time: 250}

      assert {:success, ^state, %Blackboard{next_waypoint_at: 1_250, target: nil, orientation: nil, wait_time: nil}} =
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

      assert {:failure, state, %Blackboard{next_aggro_at: 6_000}} = MobBT.try_aggro(state, blackboard, 1_000)
      assert state.unit.target == target_guid
      assert state.internal.in_combat == true
      assert state.internal.last_hostile_time == 1_000

      assert [
               %Event{type: :threat_ref_gained, target_guid: ^target_guid},
               %Event{type: :attacker_gained, target_guid: ^target_guid}
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

      assert {:failure, ^state, %Blackboard{next_aggro_at: 6_000}} = MobBT.try_aggro(state, blackboard, 1_000)
    end

    test "uses level-adjusted aggro range" do
      source_guid = mob_guid(17)
      target_guid = player_guid()

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {6.0, 0.0, 0.0}, alliance(), 30)

      assert {:failure, ^state, %Blackboard{next_aggro_at: 6_000}} = MobBT.try_aggro(state, blackboard, 1_000)
    end

    test "uses the creature detection range for aggro distance" do
      source_guid = mob_guid(17)
      target_guid = player_guid()

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17, detection_range: 10.0)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {12.0, 0.0, 0.0}, alliance(), 5)

      assert {:failure, ^state, %Blackboard{next_aggro_at: 6_000}} = MobBT.try_aggro(state, blackboard, 1_000)
      assert state.unit.target == 0
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
      blackboard = %Blackboard{next_spread_at: 0}

      assert {:success, ^state, ^blackboard} = MobBT.maybe_spread(state, blackboard, 1_000)
    end

    test "waits for the spread timer" do
      target_guid = player_guid()
      state = put_in(fixture_mob().unit.target, target_guid)
      blackboard = %Blackboard{next_spread_at: 5_000}

      assert {:success, ^state, ^blackboard} = MobBT.maybe_spread(state, blackboard, 1_000)
    end

    test "resets the spread budget when the target is moving" do
      target_guid = player_guid()
      SpatialHash.put_movement(target_guid, {0, {0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 0, 10_000})
      on_exit(fn -> SpatialHash.clear_movement(target_guid) end)

      state = put_in(fixture_mob().unit.target, target_guid)
      blackboard = %Blackboard{next_spread_at: 0, spread_attempts: 2}

      assert {:success, ^state, %Blackboard{spread_attempts: 0, next_spread_at: next}} =
               MobBT.maybe_spread(state, blackboard, 1_000)

      assert next >= 3_500 and next <= 4_500
    end

    test "stops nudging after the attempt cap" do
      target_guid = player_guid()
      state = put_in(fixture_mob().unit.target, target_guid)
      blackboard = %Blackboard{next_spread_at: 0, spread_attempts: 3}

      assert {:success, ^state, %Blackboard{spread_attempts: 3}} = MobBT.maybe_spread(state, blackboard, 1_000)
    end

    test "does nothing without a stacked neighbor" do
      target_guid = player_guid()
      state = put_in(fixture_mob().unit.target, target_guid)
      blackboard = %Blackboard{next_spread_at: 0, spread_attempts: 0}

      assert {:success, ^state, %Blackboard{spread_attempts: 0, next_spread_at: next}} =
               MobBT.maybe_spread(state, blackboard, 1_000)

      assert next >= 3_500 and next <= 4_500
    end
  end

  defp finish_current_move(%Mob{internal: %Internal{movement_start_time: start_time} = internal} = mob)
       when is_integer(start_time) do
    duration = mob.movement_block.duration || 0
    %{mob | internal: %{internal | movement_start_time: start_time - duration - 1}}
  end

  defp finish_current_move(%Mob{} = mob), do: mob

  defp fixture_mob(opts \\ []) do
    %Mob{
      object: %Object{
        guid: Keyword.get(opts, :guid, mob_guid(1))
      },
      unit: %Unit{
        level: Keyword.get(opts, :level, 1),
        faction_template: Keyword.get(opts, :faction_template, 17),
        flags: 0,
        target: 0
      },
      internal: %Internal{
        map: 0,
        in_combat: false,
        movement_start_time: Keyword.get(opts, :start_time),
        movement_start_position: Keyword.get(opts, :movement_start_position, {0.0, 0.0, 0.0}),
        creature: %Creature{detection_range: Keyword.get(opts, :detection_range)}
      },
      movement_block: %MovementBlock{
        duration: Keyword.get(opts, :duration, 0),
        position: Keyword.get(opts, :position, {0.0, 0.0, 0.0, 0.0}),
        spline_nodes: Keyword.get(opts, :spline_nodes, [{1.0, 0.0, 0.0}])
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
    rem(System.unique_integer([:positive]), max) + 1
  end

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp defias do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp wolf do
    %FactionTemplate{id: 32, faction: 29, flags: 16, faction_group: 0, friend_group: 0, enemy_group: 0, enemies_0: 28}
  end
end
