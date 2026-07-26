defmodule ThistleTea.Game.Entity.Logic.EngagementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap

  @combat_flag 0x00080000
  @tapped_flag 0x0004

  describe "enter/4" do
    test "changes all combat identity through one typed transition" do
      target = 20

      %Engagement.Result{
        entity: mob,
        from: :idle,
        to: :engaged,
        reason: :enter,
        decision: {:switch, ^target},
        previous_victim: nil,
        victim: ^target,
        victim_changed?: true
      } = Engagement.enter(mob(), target, 1_000, selection())

      assert mob.internal.in_combat
      assert mob.internal.last_hostile_time == 1_000
      assert mob.internal.threat == %{target => 0.0}
      assert mob.unit.target == target
      assert Bitwise.band(mob.unit.flags, @combat_flag) == @combat_flag
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.ThreatRefGained))
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.AttackerGained))
    end
  end

  describe "leave/3" do
    test "clears victim, threat, tap, casting-facing memory, and combat projection together" do
      target = 20
      %Engagement.Result{entity: mob} = Engagement.enter(mob(), target, 1_000, selection())
      mob = Engagement.claim(mob, %Tap{player: target, group_id: 7})

      %Engagement.Result{entity: mob, from: :engaged, to: :idle, reason: :evade} =
        Engagement.leave(mob, :evade)

      refute mob.internal.in_combat
      assert mob.internal.threat == %{}
      assert mob.internal.loot.tapped_by == nil
      assert mob.unit.target == 0
      assert Bitwise.band(mob.unit.flags, @combat_flag) == 0
      assert Bitwise.band(mob.unit.dynamic_flags, @tapped_flag) == 0
      refute mob.internal.blackboard.combat.auto_attacking
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.AttackStop))
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.ThreatRefLost))
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.TapCleared))
    end
  end

  describe "die/1" do
    test "releases combat identity while preserving corpse tap ownership" do
      target = 20
      %Engagement.Result{entity: mob} = Engagement.enter(mob(), target, 1_000, selection())
      mob = Engagement.claim(mob, %Tap{player: target})
      mob = %{mob | unit: %{mob.unit | health: 0}}

      %Engagement.Result{entity: mob, from: :engaged, to: :dead, reason: :death} = Engagement.die(mob)

      refute mob.internal.in_combat
      assert mob.internal.threat == %{}
      assert mob.internal.loot.tapped_by == %Tap{player: target}
      assert mob.unit.target == 0
      assert Bitwise.band(mob.unit.dynamic_flags, @tapped_flag) == @tapped_flag
      refute Enum.any?(mob.internal.events, &is_struct(&1, Effects.TapCleared))
    end
  end

  defp mob do
    %Mob{
      object: %Object{guid: 10},
      unit: %Unit{health: 100, max_health: 100, flags: 0, dynamic_flags: 0, target: 0},
      internal: %Internal{
        in_combat: false,
        threat: %{},
        loot: %Loot{},
        blackboard: %Blackboard{
          combat: %Blackboard.Combat{auto_attacking: true, attack_started: true}
        }
      }
    }
  end

  defp selection do
    [selection: [valid?: fn _guid -> true end, in_melee?: fn _guid -> false end]]
  end
end
