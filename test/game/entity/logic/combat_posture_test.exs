defmodule ThistleTea.Game.Entity.Logic.CombatPostureTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  setup [:character]

  describe "receive_attack/4" do
    test "a seated critical hit preserves damage and attacker procs without triggering the victim", %{character: c} do
      c = seated(c, [proc_holder(100, 8, 2)])
      {damaged, events} = Combat.receive_attack(c, attack(), 2_000, roll: 9_999)

      assert damaged.unit.health == 980
      assert damaged.unit.stand_state == 0
      assert [%Holder{charges: 3, next_proc_at: nil}] = damaged.unit.auras
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
      assert [%Effects.StandState{stand_state: 0}] = posture_events(damaged)
      assert %Effects.AttackerStateUpdate{damage: 20, attack: %{hit_info: 0x82}} = hd(events)

      feedback = Enum.find(events, &is_struct(&1, Effects.AttackOutcome))
      assert %Effects.AttackOutcome{outcome: :crit, proc_ex: 2} = feedback
      attacker = %{c | object: %Object{guid: 1}, unit: %{c.unit | stand_state: 0, auras: [proc_holder(200, 4, 2)]}}

      payload = %{
        victim_guid: c.object.guid,
        outcome: feedback.outcome,
        damage: feedback.damage,
        proc_ex: feedback.proc_ex
      }

      attacker = AttackFeedback.receive(attacker, payload, nil, 2_000)
      assert Enum.any?(attacker.internal.events, &match?(%Effects.TriggerSpell{spell_id: 201}, &1))
    end

    test "standing critical hits still spend defensive proc charges and start their cooldown", %{character: c} do
      c = %{c | unit: %{c.unit | auras: [proc_holder(100, 8, 2)]}}
      {damaged, events} = Combat.receive_attack(c, %{attack() | crit_chance: 100}, 2_000, roll: 9_999)

      assert damaged.unit.health == 980
      assert [%Holder{charges: 2, next_proc_at: 5_000}] = damaged.unit.auras
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 101}, &1))
      assert posture_events(damaged) == []
    end

    test "a seated absorbed crit retains absorb procs", %{character: c} do
      shield = %Holder{spell: %Spell{id: 300}, auras: [%Aura{type: :school_absorb, amount: 50, misc_value: 1}]}
      c = seated(c, [proc_holder(100, 8, 2), proc_holder(200, 8, 0x400), shield])
      {damaged, events} = Combat.receive_attack(c, attack(), 2_000, roll: 9_999)

      assert damaged.unit.health == 1000
      assert damaged.unit.stand_state == 0
      assert holder(damaged, 100).charges == 3
      assert holder(damaged, 200).charges == 2
      assert hd(holder(damaged, 300).auras).amount == 30
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 201}, &1))
      refute Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 101}, &1))
      assert Enum.any?(events, &match?(%Effects.AttackOutcome{proc_ex: 0x402}, &1))
    end
  end

  describe "take_damage/4" do
    test "direct damage stands all seated poses and removes sitting-only auras once", %{character: c} do
      food = %Holder{spell: %Spell{id: 400, aura_interrupt_flags: 0x40000}, auras: [%Aura{type: :dummy}]}

      for posture <- [1, 3, 4, 5, 6, 8] do
        c = %{c | unit: %{c.unit | stand_state: posture, auras: [food]}}
        damaged = c |> Core.take_damage(10, 2_000) |> Core.take_damage(10, 2_100)
        assert damaged.unit.health == 980
        assert damaged.unit.stand_state == 0
        assert damaged.unit.auras == []
        assert posture_events(damaged) == [%Effects.StandState{stand_state: 0}]
      end
    end

    test "periodic damage and mounted players retain their posture", %{character: c} do
      sitting = seated(c, [])
      damaged = Core.take_damage(sitting, 10, 2_000, periodic: true)
      assert damaged.unit.health == 990
      assert damaged.unit.stand_state == 1
      assert posture_events(damaged) == []

      mount = %Holder{spell: %Spell{id: 500}, auras: [%Aura{type: :mounted}]}
      damaged = c |> seated([mount]) |> Core.take_damage(10, 2_000)
      assert damaged.unit.stand_state == 1
      assert posture_events(damaged) == []
    end

    test "immune and godmode players do not change posture", %{character: c} do
      immunity = %Holder{spell: %Spell{id: 600}, auras: [%Aura{type: :damage_immunity, misc_value: 1}]}
      immune = seated(c, [immunity])
      assert Core.take_damage(immune, 10, 2_000) == immune
      godmode = %{seated(c, []) | internal: %{c.internal | godmode: true}}
      assert Core.take_damage(godmode, 10, 2_000) == godmode
    end

    test "creature postures and dead actors are not forced to stand", %{character: c} do
      mob = %Mob{unit: %{c.unit | stand_state: 1}, object: c.object, internal: c.internal}
      assert Core.take_damage(mob, 10, 2_000).unit.stand_state == 1
      dead = %{c | unit: %{c.unit | health: 0, stand_state: 7}}
      assert Emote.on_damage(dead, 2_000) == dead
      assert Emote.standing?(dead)
    end
  end

  describe "roll_special/3" do
    test "seated physical abilities crit before avoidance even with no base crit chance", %{character: c} do
      dodge = %Holder{spell: %Spell{id: 700}, auras: [%Aura{type: :mod_dodge, amount: 100}]}
      c = seated(c, [dodge])

      for class <- [2, 3] do
        attack = Map.merge(attack(), %{crit_chance: 0, spell_damage_class: class})
        assert %{outcome: :crit, crit?: true} = AttackTable.roll_special(c, attack, roll: 0, crit_roll: 9_999)
      end
    end

    test "cannot-crit and mechanic resistance retain precedence over seated crits", %{character: c} do
      c = seated(c, [])
      attack = Map.merge(attack(), %{crit_chance: 100, can_crit?: false, spell_damage_class: 2})
      assert %{outcome: :normal, crit?: false} = AttackTable.roll_special(c, attack, roll: 9_999, crit_roll: 0)

      resistance = %Holder{
        spell: %Spell{id: 800},
        auras: [%Aura{type: :mechanic_resistance, amount: 100, misc_value: 1}]
      }

      c = seated(c, [resistance])
      attack = Map.merge(attack(), %{mechanic: 1, spell_damage_class: 2})
      assert %{outcome: :resist, crit?: false} = AttackTable.roll_special(c, attack, roll: 0)
    end
  end

  describe "receive/4" do
    test "seated melee and ranged ability crits still trigger defensive talents", %{character: c} do
      for class <- [2, 3] do
        c = seated(c, [proc_holder(100, 0x2A8, 2)])
        spell = damage_spell(class)
        {damaged, events} = SpellEffect.receive(c, cast_context(), spell, 2_000)

        assert damaged.unit.health == 980
        assert damaged.unit.stand_state == 0
        assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 20, crit?: true}, &1))
        assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 101}, &1))
        assert holder(damaged, 100).charges == 2
      end
    end

    test "sitting does not force magic or cannot-crit spell damage to crit", %{character: c} do
      for spell <- [
            damage_spell(1),
            %{damage_spell(2) | attributes: MapSet.new([:cant_crit])},
            %{damage_spell(3) | attributes: MapSet.new([:cant_crit])}
          ] do
        {damaged, events} = SpellEffect.receive(seated(c, []), cast_context(), spell, 2_000)
        assert damaged.unit.health == 990
        assert damaged.unit.stand_state == 0
        assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 10, crit?: false}, &1))
      end
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 2},
        player: %Player{flags: 0},
        unit: %Unit{
          health: 1_000,
          max_health: 1_000,
          level: 60,
          class: 1,
          agility: 0,
          normal_resistance: 0,
          auras: [],
          stand_state: 0
        },
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp seated(character, auras), do: %{character | unit: %{character.unit | stand_state: 1, auras: auras}}
  defp posture_events(character), do: Enum.filter(character.internal.events, &is_struct(&1, Effects.StandState))
  defp holder(character, id), do: Enum.find(character.unit.auras, &(&1.spell.id == id))

  defp attack do
    %{caster: 1, caster_level: 60, caster_player?: true, crit_chance: 5, damage: 10}
  end

  defp proc_holder(id, flags, mask) do
    %Holder{
      spell: %Spell{
        id: id,
        proc_type_mask: flags,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_ex: mask, cooldown_ms: 3_000}
      },
      caster_guid: 2,
      caster_level: 60,
      charges: 3,
      auras: [%Aura{type: :proc_trigger_spell, trigger_spell_id: id + 1}]
    }
  end

  defp damage_spell(class) do
    %Spell{
      id: 900,
      school: :physical,
      dmg_class: class,
      effects: [%Effect{index: 0, type: :school_damage, base_points: 10, implicit_target_a: :target_enemy}]
    }
  end

  defp cast_context do
    %CastContext{
      caster_guid: 1,
      caster_level: 60,
      caster_type: :player,
      melee_crit_chance: 0.0,
      spell_crit_chance: 0.0,
      hit_chance_bonus: 100
    }
  end
end
