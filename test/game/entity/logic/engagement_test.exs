defmodule ThistleTea.Game.Entity.Logic.EngagementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast

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

    test "keeps an explicitly commanded pet victim while tracking another attacker" do
      commanded_target = 20
      other_attacker = 30

      pet =
        mob()
        |> then(fn mob ->
          %{
            mob
            | unit: %{mob.unit | target: commanded_target},
              internal: %{
                mob.internal
                | pet: %Pet{command_state: :attack},
                  in_combat: true,
                  threat: %{commanded_target => 0.0}
              }
          }
        end)

      %Engagement.Result{entity: pet, decision: :keep} = Engagement.enter(pet, other_attacker, 2_000)

      assert pet.unit.target == commanded_target
      assert pet.internal.threat == %{commanded_target => 0.0, other_attacker => 0.0}
    end

    test "refuses renewed combat until return-home movement finishes" do
      %{entity: creature} = Engagement.enter(mob(), 20, 1_000, selection())
      %{entity: creature} = Engagement.leave(creature, :evade)
      blackboard = creature.internal.blackboard
      blackboard = %{blackboard | navigation: %{blackboard.navigation | returning_home?: true}}
      creature = %{creature | internal: %{creature.internal | blackboard: blackboard}}

      assert %Engagement.Result{entity: ^creature, from: :idle, to: :idle, reason: :evading} =
               Engagement.enter(creature, 30, 2_000, selection())

      blackboard = Blackboard.clear_move_target(blackboard)
      creature = %{creature | internal: %{creature.internal | blackboard: blackboard}}
      %{entity: creature, to: :engaged} = Engagement.enter(creature, 30, 3_000, selection())

      assert creature.internal.threat == %{30 => 0.0}
      assert creature.unit.target == 30
      assert creature.internal.combat_leash.generation == 2
      assert creature.internal.combat_leash.last_extended_at == 3_000
    end
  end

  describe "stop_attack/1" do
    test "stops melee and queued abilities while retaining the rest of the engagement" do
      %{entity: mob} = Engagement.enter(mob(), 20, 1_000, selection())
      mob = Engagement.claim(mob, %Tap{player: 20, group_id: 7})
      casting = %Cast{spell: %Spell{id: 116}, phase: :preparing}
      blackboard = mob.internal.blackboard
      blackboard = %{blackboard | combat: %{blackboard.combat | next_attack_at: 12_345}}

      mob = %{
        mob
        | internal: %{
            mob.internal
            | casting: casting,
              next_swing_spell: %Spell{id: 78},
              blackboard: blackboard,
              events: []
          }
      }

      assert %Engagement.Result{
               entity: stopped,
               from: :engaged,
               to: :engaged,
               previous_victim: 20,
               victim: nil,
               victim_changed?: true
             } = Engagement.stop_attack(mob)

      assert stopped.internal.threat == mob.internal.threat
      assert stopped.internal.loot == mob.internal.loot
      assert stopped.internal.combat_leash == mob.internal.combat_leash
      assert stopped.movement_block == mob.movement_block
      assert stopped.unit.flags == mob.unit.flags
      assert stopped.internal.casting == casting
      assert stopped.internal.blackboard.combat.next_attack_at == 12_345
      refute stopped.internal.blackboard.combat.attack_started
      assert stopped.internal.next_swing_spell == nil
      assert Enum.any?(stopped.internal.events, &match?(%Effects.AttackStop{target_guid: 20}, &1))
      assert Enum.any?(stopped.internal.events, &match?(%Effects.AttackerLost{target_guid: 20}, &1))

      assert Enum.any?(
               stopped.internal.events,
               &match?(%Effects.SpellCastFailed{spell_id: 78, reason: :interrupted}, &1)
             )

      assert Engagement.stop_attack(stopped).entity == stopped
      assert Engagement.enter(stopped, 20, 2_000, selection()).entity.unit.target == 20
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

  describe "on_damage/3" do
    test "first damage selects the attacker so the combat tree can run" do
      mob = Engagement.on_damage(mob(), 20, 1_000)
      assert mob.internal.in_combat
      assert mob.unit.target == 20
      assert Enum.any?(mob.internal.events, &match?(%Effects.AttackerGained{target_guid: 20}, &1))
      assert Engagement.on_damage(mob, 30, 2_000) == mob
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
