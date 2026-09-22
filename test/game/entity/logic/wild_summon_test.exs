defmodule ThistleTea.Game.Entity.Logic.WildSummonTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Passive
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.AI.TickPlan
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.TemporarySummon
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:mob]

  describe "SpellEffect.receive/4" do
    test "summons once on the caster with count and destination", %{mob: mob} do
      spell = spell()
      context = %CastContext{caster_guid: 7, caster_level: 20, destination_position: {10.0, 20.0, 30.0}}
      assert {^mob, [%Effects.SummonWild{} = effect]} = SpellEffect.receive(mob, context, spell, 1000)
      assert effect.count == 3
      assert effect.position == {10.0, 20.0, 30.0, 0.0}
      assert effect.duration_ms == 5000
      assert effect.scatter?
      assert {^mob, []} = SpellEffect.receive(mob, %{context | caster_guid: 8}, spell, 1000)
    end

    test "uses the forward radius without a destination and normalizes indefinite lifetime", %{mob: mob} do
      spell = %{spell() | duration_ms: -1}
      context = %CastContext{caster_guid: 7, caster_level: 20}
      assert {^mob, [%Effects.SummonWild{} = effect]} = SpellEffect.receive(mob, context, spell, 1000)
      assert effect.position == {2.0, 0.0, 0.0, 0.0}
      assert effect.duration_ms == 0
      refute effect.scatter?
    end
  end

  describe "TemporarySummon.tick/2" do
    test "defers timed death until combat ends without extending the deadline", %{mob: mob} do
      assert TemporarySummon.tick(mob, 4999) == mob
      fighting = %{mob | internal: %{mob.internal | in_combat: true}}
      assert TemporarySummon.tick(fighting, 6000) == fighting
      assert TemporarySummon.next_at(fighting, 6000) == 6100
      dead = TemporarySummon.tick(mob, 6000)
      assert dead.unit.health == 0
      assert dead.internal.killed_by == 7
      assert dead.internal.loot.tapped_by == %Tap{player: 1}
      assert TemporarySummon.tick(dead, 7000) == dead
      assert TemporarySummon.next_at(dead, 7000) == nil
    end

    test "decoys die during combat and clear combat through the shared transition", %{mob: mob} do
      mob = %{
        mob
        | unit: %{mob.unit | target: 9},
          internal: %{
            mob.internal
            | in_combat: true,
              threat: %{9 => 100},
              spawn: %{mob.internal.spawn | death_in_combat?: true}
          }
      }

      dead = TemporarySummon.tick(mob, 5000)
      assert dead.unit.health == 0
      assert dead.unit.target == 0
      refute dead.internal.in_combat
      assert dead.internal.threat == %{}
      assert %Effects.AttackerLost{target_guid: 9} in dead.internal.events
      assert %Effects.MovementStopped{} in dead.internal.events
    end
  end

  describe "BehaviorRunner.tick/3" do
    test "passive creatures never chase or melee and schedule their death deadline", %{mob: mob} do
      mob = BT.init(mob, Passive.tree())
      mob = %{mob | unit: %{mob.unit | target: 9}, internal: %{mob.internal | in_combat: true}}
      {status, result} = BehaviorRunner.tick(Passive.tree(), mob, Context.new(4500))
      assert result.internal.navigation_intents == []
      assert result.internal.events == []
      assert TickPlan.next(Tick.plan(result, status, 4500)) == %TickPlan.Wake{at: 5000, source: :summon_death}
    end
  end

  defp spell do
    %Spell{
      id: 100,
      duration_ms: 5000,
      effects: [%Effect{type: :summon_wild, misc_value: 123, base_points: 2, base_dice: 1, radius_yards: 2.0}]
    }
  end

  defp mob(_context) do
    %{
      mob: %Mob{
        object: %Object{guid: 7},
        unit: %Unit{level: 20, health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          in_combat: false,
          threat: %{},
          creature: %Creature{regenerate_stats: 0},
          loot: %Loot{tapped_by: %Tap{player: 1}},
          spawn: %Spawn{temporary?: true, despawn_type: 11, death_at: 5000}
        }
      }
    }
  end
end
