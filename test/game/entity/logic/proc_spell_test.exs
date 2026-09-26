defmodule ThistleTea.Game.Entity.Logic.ProcSpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ProcSpell
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  setup [:character]

  describe "resolve/4" do
    test "each Blessed Recovery rank returns three ticks of its damage percentage" do
      for {id, percent, trigger} <- [{27_811, 8, 27_813}, {27_815, 16, 27_817}, {27_816, 25, 27_818}] do
        holder = holder(recovery(id, percent))
        event = Effects.trigger_spell(1, 60, 2, 18_350, triggered_by_spell_id: id, cast_item_guid: 99)
        [resolved] = ProcSpell.resolve(event, holder, %{damage: 300}, fn -> 0.0 end)
        assert resolved.spell_id == trigger
        assert resolved.target_guid == 1
        assert resolved.amount == percent
        assert resolved.slot == 0
        assert resolved.triggering_spell_id == id
        assert resolved.cast_item_guid == 99
        assert resolved.requires_living_target?
      end
    end

    test "fractional recovery uses unbiased rounding" do
      holder = holder(recovery())
      event = Effects.trigger_spell(1, 60, 2, 18_350)
      assert [%{amount: 8}] = ProcSpell.resolve(event, holder, %{damage: 100}, fn -> 0.0 end)
      assert [%{amount: 9}] = ProcSpell.resolve(event, holder, %{damage: 100}, fn -> 0.999 end)
      assert ProcSpell.resolve(event, holder, %{damage: 0}) == []
      assert ProcSpell.resolve(event, holder, %{}) == []
    end

    test "Persistent Shield uses the complete heal amount and keeps its recipient" do
      event = Effects.trigger_spell(1, 60, 2, 13_567)
      holder = holder(shield_proc())
      [resolved] = ProcSpell.resolve(event, holder, %{damage: 1_001, victim_alive?: true})
      assert resolved.spell_id == 26_470
      assert resolved.target_guid == 2
      assert resolved.amount == 150
      assert ProcSpell.resolve(event, holder, %{damage: 1_001, victim_alive?: false}) == []
      assert ProcSpell.resolve(event, holder, %{damage: 0, victim_alive?: true}) == []
    end
  end

  describe "reactions/3" do
    test "only critical weapon attacks trigger Blessed Recovery", %{character: character} do
      character = with_aura(character, recovery())

      for type <- [:take_melee_swing, :take_melee_ability, :take_ranged_attack, :take_ranged_ability] do
        context = %{attacker_guid: 2, proc_type: type, outcome: :crit, damage: 300, now: 0}

        assert {_, [%Effects.TriggerSpell{target_guid: 1, spell_id: 27_818, amount: 25}]} =
                 Aura.reactions(character, :hit_taken, context)

        assert {^character, []} = Aura.reactions(character, :hit_taken, %{context | outcome: :normal})
      end

      context = %{
        attacker_guid: 2,
        proc_type: :take_harmful_spell,
        outcome: :crit,
        damage: 300,
        now: 0,
        spell: %Spell{}
      }

      assert {^character, []} = Aura.reactions(character, :spell_hit_taken, context)
    end

    test "custom procs retain shared cooldown and charge transitions", %{character: character} do
      spell = %{recovery() | proc_charges: 2, proc_rule: %ProcRule{proc_ex: 2, cooldown_ms: 1_000}}
      character = with_aura(character, spell)
      context = %{attacker_guid: 2, proc_type: :take_melee_swing, outcome: :crit, damage: 300, now: 0}
      {character, [_]} = Aura.reactions(character, :hit_taken, context)
      assert hd(character.unit.auras).charges == 1
      assert {^character, []} = Aura.reactions(character, :hit_taken, %{context | now: 999})
      {character, [_]} = Aura.reactions(character, :hit_taken, %{context | now: 1_000})
      assert character.unit.auras == []
    end

    test "Persistent Shield reacts to direct healing rather than damage or periodic healing", %{character: character} do
      character = with_aura(character, shield_proc())

      context = %{
        victim_guid: 2,
        victim_alive?: true,
        proc_type: :deal_helpful_spell,
        outcome: :normal,
        damage: 600,
        spell: %Spell{id: 900, effects: [%Effect{type: :heal}]},
        now: 0
      }

      assert {_, [%Effects.TriggerSpell{target_guid: 2, spell_id: 26_470, amount: 90}]} =
               Aura.reactions(character, :spell_hit_dealt, context)

      for type <- [:deal_harmful_spell, :deal_helpful_periodic] do
        assert {^character, []} = Aura.reactions(character, :spell_hit_dealt, %{context | proc_type: type})
      end
    end
  end

  describe "receive_attack/4" do
    test "recovery uses damage after absorption and never fires on lethal hits", %{character: character} do
      character = character |> with_aura(recovery()) |> with_aura(absorb(100))
      attack = %{caster: 2, caster_level: 60, damage: 200, crit_chance: 100.0}
      {damaged, events} = Combat.receive_attack(character, attack, 0, roll: 9_999)
      assert damaged.unit.health == 4_700
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 27_818, amount: 25}, &1))

      {_dead, events} = Combat.receive_attack(character, %{attack | damage: 5_000}, 0, roll: 9_999)
      refute Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 27_818}, &1))
    end
  end

  describe "apply/5" do
    test "melee ability feedback retains its damage after absorption", %{character: character} do
      character = character |> with_aura(recovery()) |> with_aura(absorb(100))
      effect = %Effect{index: 0, type: :school_damage, base_points: 200}
      spell = %Spell{id: 901, school: :physical, dmg_class: 2, effects: [effect]}
      context = %CastContext{caster_guid: 2, caster_level: 60, spell: spell, melee_crit?: true}
      {damaged, events} = DamageHeal.apply(character, context, spell, effect, 0)
      assert damaged.unit.health == 4_700
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 27_818, amount: 25}, &1))
    end
  end

  defp recovery(id \\ 27_816, percent \\ 25) do
    %Spell{
      id: id,
      proc_type_mask: 0x2A8,
      proc_chance: 100,
      proc_rule: %ProcRule{proc_ex: 2},
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :proc_trigger_spell, base_points: percent, trigger_spell_id: 18_350}
      ]
    }
  end

  defp shield_proc do
    %Spell{
      id: 26_467,
      proc_type_mask: 0x4000,
      proc_chance: 100,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :proc_trigger_spell, trigger_spell_id: 13_567}]
    }
  end

  defp absorb(amount) do
    %Spell{
      id: 902,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :school_absorb, base_points: amount, misc_value: 127}]
    }
  end

  defp holder(spell) do
    [effect] = spell.effects
    %Holder{spell: spell, auras: [%AuraData{type: :proc_trigger_spell, amount: effect.base_points}]}
  end

  defp with_aura(character, spell) do
    {character, _} = Aura.apply_spell(character, 1, 60, spell, 0)
    character
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 5_000, max_health: 5_000, level: 60, normal_resistance: 0, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{character: character}
  end
end
