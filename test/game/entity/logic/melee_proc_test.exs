defmodule ThistleTea.Game.Entity.Logic.MeleeProcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Combat, as: CombatSink
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.ProcRule

  setup [:combatants]

  describe "receive_attack/4" do
    test "avoided outgoing attacks only activate explicitly matching proc rules", %{
      attacker: attacker,
      defender: defender
    } do
      {_defender, events} = Combat.receive_attack(defender, attack(attacker, 100), 1_000, roll: 0)
      feedback = Enum.find(events, &is_struct(&1, Effects.AttackOutcome))
      assert feedback.proc_ex == 4
      CombatSink.emit(defender, feedback, nil)
      assert_receive {:"$gen_cast", {:attack_outcome, payload}}
      assert AttackFeedback.receive(attacker, payload, 1_000).internal.events == []

      [holder] = attacker.unit.auras
      holder = %{holder | spell: %{holder.spell | proc_rule: %ProcRule{proc_ex: 4}}}
      attacker = %{attacker | unit: %{attacker.unit | auras: [holder]}}
      assert triggered_ids(AttackFeedback.receive(attacker, payload, 1_000).internal.events) == [9_004]
    end

    test "Sweeping Strikes copies a partially blocked hit and spends one charge", %{
      attacker: attacker,
      defender: defender
    } do
      holder = %Holder{
        spell: %Spell{id: 12_292, proc_type_mask: 0x14, proc_chance: 100},
        charges: 5,
        auras: [%Aura{type: :dummy}]
      }

      attacker = %{attacker | unit: %{attacker.unit | auras: [holder]}}
      {_defender, events} = Combat.receive_attack(defender, attack(attacker, 100), 1_000, roll: 2_500)
      CombatSink.emit(defender, Enum.find(events, &is_struct(&1, Effects.AttackOutcome)), nil)
      assert_receive {:"$gen_cast", {:attack_outcome, payload}}
      updated = AttackFeedback.receive(attacker, payload, 1_000)
      assert [%Effects.SecondaryMelee{damage: 88}] = updated.internal.events
      assert hd(updated.unit.auras).charges == 4
    end

    test "partial blocks carry landed and absorbed results through both owners", %{
      attacker: attacker,
      defender: defender
    } do
      for {absorbed, expected_mask} <- [{0, 0x41}, {50, 0x441}, {100, 0x441}] do
        defender = with_absorb(defender, absorbed)
        {updated, events} = Combat.receive_attack(defender, attack(attacker, 100), 1_000, roll: 2_500)
        feedback = Enum.find(events, &is_struct(&1, Effects.AttackOutcome))

        assert feedback.outcome == :block
        assert feedback.proc_ex == expected_mask
        assert feedback.damage == max(88 - absorbed, 0)
        assert updated.unit.health == 500 - max(88 - absorbed, 0)
        assert Enum.sort(triggered_ids(events)) == [9_001, 9_002, 9_003]
        assert Enum.find(updated.unit.auras, &(&1.spell.id == 1)).charges == 1

        CombatSink.emit(updated, feedback, nil)
        assert_receive {:"$gen_cast", {:attack_outcome, payload}}
        assert payload.proc_ex == expected_mask
        result = AttackFeedback.receive(attacker, payload, 1_000)
        assert triggered_ids(result.internal.events) == [9_004]
        assert hd(result.unit.auras).charges == 1
      end
    end

    test "full blocks trigger block reactions and damage shields without ordinary procs", %{
      attacker: attacker,
      defender: defender
    } do
      {updated, events} = Combat.receive_attack(defender, attack(attacker, 10), 1_000, roll: 2_500)
      feedback = Enum.find(events, &is_struct(&1, Effects.AttackOutcome))
      assert feedback.proc_ex == 0x40
      assert feedback.damage == 0
      assert updated.unit.health == 500
      assert Enum.sort(triggered_ids(events)) == [9_002, 9_003]
      assert Enum.find(updated.unit.auras, &(&1.spell.id == 1)).charges == 2

      CombatSink.emit(updated, feedback, nil)
      assert_receive {:"$gen_cast", {:attack_outcome, payload}}
      result = AttackFeedback.receive(attacker, payload, 1_000)
      assert triggered_ids(result.internal.events) == []
      assert hd(result.unit.auras).charges == 2
    end

    test "fully absorbed normal hits permit aura procs but suppress ordinary damage shields", %{
      attacker: attacker,
      defender: defender
    } do
      {updated, events} = Combat.receive_attack(with_absorb(defender, 100), attack(attacker, 100), 1_000, roll: 9_999)
      feedback = Enum.find(events, &is_struct(&1, Effects.AttackOutcome))
      assert feedback.proc_ex == 0x401
      assert feedback.damage == 0
      assert updated.unit.health == 500
      assert triggered_ids(events) == [9_001]
    end

    test "partially absorbed hits still trigger damage shields", %{attacker: attacker, defender: defender} do
      for absorbed <- [40, 60, 99] do
        {updated, events} =
          Combat.receive_attack(with_absorb(defender, absorbed), attack(attacker, 100), 1_000, roll: 9_999)

        assert updated.unit.health == 400 + absorbed
        assert Enum.sort(triggered_ids(events)) == [9_001, 9_003]
      end
    end

    test "incoming proc cooldowns hold charges until the next eligible hit", %{attacker: attacker, defender: defender} do
      [incoming | _] = defender.unit.auras
      incoming = %{incoming | spell: %{incoming.spell | proc_rule: %ProcRule{cooldown_ms: 1_000}}}
      defender = %{defender | unit: %{defender.unit | auras: [incoming]}}
      {defender, events} = Combat.receive_attack(defender, attack(attacker, 100), 1_000, roll: 2_500)
      assert triggered_ids(events) == [9_001]
      assert hd(defender.unit.auras).next_proc_at == 2_000

      {defender, events} = Combat.receive_attack(defender, attack(attacker, 100), 1_999, roll: 2_500)
      assert triggered_ids(events) == []
      assert hd(defender.unit.auras).charges == 1

      {defender, events} = Combat.receive_attack(defender, attack(attacker, 100), 2_000, roll: 2_500)
      assert triggered_ids(events) == [9_001]
      assert defender.unit.auras == []
    end

    test "Retaliation consumes a charge on partial blocks but not full blocks", %{
      attacker: attacker,
      defender: defender
    } do
      retaliation = %Holder{
        spell: %Spell{id: 20_230, proc_type_mask: 0x8, proc_chance: 100},
        caster_guid: defender.object.guid,
        charges: 30,
        auras: [%Aura{type: :dummy}]
      }

      defender = %{defender | unit: %{defender.unit | auras: [retaliation]}}

      for {damage, charges, triggers} <- [{100, 29, [22_858]}, {10, 30, []}] do
        {result, events} = Combat.receive_attack(defender, attack(attacker, damage), 1_000, roll: 2_500)
        assert hd(result.unit.auras).charges == charges
        assert triggered_ids(events) == triggers
      end
    end
  end

  defp combatants(_context) do
    attacker_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    Entity.register(attacker_guid)
    on_exit(fn -> Entity.unregister(attacker_guid) end)

    attacker = entity(attacker_guid, [proc_holder(4, 0x4)])

    block = %{
      proc_holder(2, 0x8)
      | spell: %Spell{id: 2, proc_type_mask: 0x8, proc_chance: 100, proc_rule: %ProcRule{proc_ex: 0x40}}
    }

    shield = %Holder{
      spell: %Spell{id: 3},
      caster_guid: 2,
      auras: [%Aura{type: :damage_shield, trigger_spell_id: 9_003}]
    }

    %{attacker: attacker, defender: entity(2, [proc_holder(1, 0x8), block, shield])}
  end

  defp entity(guid, holders) do
    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 500, max_health: 500, level: 20, strength: 40, auras: holders},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{}
    }
  end

  defp proc_holder(id, flags) do
    %Holder{
      spell: %Spell{id: id, proc_type_mask: flags, proc_chance: 100},
      caster_guid: 2,
      charges: 2,
      auras: [%Aura{type: :proc_trigger_spell, trigger_spell_id: 9_000 + id}]
    }
  end

  defp with_absorb(entity, 0), do: entity

  defp with_absorb(entity, amount) do
    holder = %Holder{
      spell: %Spell{id: 17},
      caster_guid: 2,
      auras: [%Aura{type: :school_absorb, amount: amount, misc_value: 1}]
    }

    %{entity | unit: %{entity.unit | auras: [holder | entity.unit.auras]}}
  end

  defp attack(attacker, damage) do
    %{
      caster: attacker.object.guid,
      caster_level: 20,
      caster_player?: true,
      caster_position: {2.0, 0.0, 0.0},
      damage: damage
    }
  end

  defp triggered_ids(events) do
    for %Effects.TriggerSpell{spell_id: id} <- events, do: id
  end
end
