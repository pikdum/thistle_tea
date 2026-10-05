defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyWarRiderTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyWarRider
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  describe "on_spawned/4" do
    test "the six attackers fly to the opposing base before beginning their patrol" do
      for entry <- AlteracValleyWarRider.entries() do
        mob = creature(entry)
        {flying, board} = EventAI.on_spawned(mob, Blackboard.new(), 0, Context.new(0))
        home = if entry in [14_943, 14_944, 14_945], do: {618.4, -87.97, 85.77}, else: {-1311.53, -355.28, 130.93}
        assert flying.internal.creature.script_flight
        assert flying.internal.creature.caster_chase_distance == 25
        assert flying.internal.creature.reaction_state == :passive
        assert flying.internal.spawn.position == home
        assert flying.internal.spawn.distance == 55
        assert [%{destination: ^home}] = flying.internal.navigation_intents
        assert board.event_ai.phase == 0
        {patrolling, board} = EventAI.on_movement_inform(flying, board, 9, 1, Context.new(1_000))
        assert board.event_ai.phase == 1
        assert patrolling.internal.creature.reaction_state == :aggressive
      end
    end
  end

  describe "tick/4" do
    test "acquisition waits for arrival and selects the nearest hostile within fifty yards" do
      mob = creature(14_943)
      target = Guid.from_low_guid(:player, Unique.integer())
      context = context(mob, target, 40.0)
      {flying, board} = EventAI.on_spawned(mob, Blackboard.new(), 0, context)
      {waiting, _} = EventAI.tick(flying, board, 0, context)
      refute Enum.any?(waiting.internal.events, &is_struct(&1, Effects.StartAttack))
      {patrolling, board} = EventAI.on_movement_inform(flying, board, 9, 1, context)
      {attacking, _} = EventAI.tick(patrolling, board, 0, context)
      assert %Effects.StartAttack{target_guid: target} in attacking.internal.events
      {outside, _} = EventAI.tick(patrolling, board, 0, context(mob, target, 51.0))
      refute Enum.any?(outside.internal.events, &is_struct(&1, Effects.StartAttack))
    end

    test "Fireball is immediately available within thirty yards and withheld beyond it" do
      mob = creature(14_943)
      target = Guid.from_low_guid(:player, Unique.integer())
      mob = %{mob | unit: %{mob.unit | target: target}, internal: %{mob.internal | in_combat: true}}
      near = context(mob, target, 25.0)
      {mob, board} = EventAI.enter_combat(mob, Blackboard.new(), target, 0, near)
      {casting, _} = EventAI.tick(mob, board, 0, near)
      assert %{spell: %{id: 22_088}} = casting.internal.casting
      assert Enum.any?(casting.internal.events, &match?(%Effects.SpellStart{spell_id: 22_088}, &1))
      {outside, _} = EventAI.tick(mob, board, 0, context(mob, target, 31.0))
      assert outside.internal.casting == nil
    end
  end

  defp context(mob, target, distance) do
    friendly = %FactionTemplate{faction: 1, enemy_group: 2, faction_group: 1}
    hostile = %FactionTemplate{faction: 2, enemy_group: 1, faction_group: 2}

    entities = %{
      mob.object.guid => %Observation{
        guid: mob.object.guid,
        position: {mob.internal.world, 0.0, 0.0, 0.0},
        metadata: %{faction_template: friendly}
      },
      target => %Observation{
        guid: target,
        position: {mob.internal.world, distance, 0.0, 0.0},
        distance: distance,
        metadata: %{faction_template: hostile, alive?: true}
      }
    }

    perception = Perception.new(0, mob.object.guid, entities, %{players: [{target, distance}]})
    condition = %Condition{type: :distance_to_target, value1: 30, value2: 2}
    Context.new(0, perception: perception, script_conditions: %{condition => distance <= 30})
  end

  defp creature(entry) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, level: 60, flags: 0, power1: 100, max_power1: 100},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0},
      internal: %Internal{
        world: WorldRef.instance(30, Unique.integer()),
        creature: %Creature{ai_events: CreatureScript.events(entry)},
        spellbook: %{22_088 => fireball()},
        spawn: %Spawn{position: {0.0, 0.0, 0.0}}
      }
    }
  end

  defp fireball do
    %Spell{
      id: 22_088,
      cast_time_ms: 3_000,
      range_yards: 30.0,
      school: :fire,
      mana_cost: 0,
      power_type: 0,
      effects: [%Effect{type: :school_damage, base_points: 20, implicit_target_a: :target_enemy}]
    }
  end
end
