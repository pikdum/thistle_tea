defmodule ThistleTea.Game.Spell.ModifiersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers

  describe "value/4" do
    test "applies flat and percent modifiers selected by DBC family masks" do
      entity =
        entity([
          modifier_holder(:add_flat_modifier, 25, 7, 0x4),
          modifier_holder(:add_pct_modifier, 50, 7, 0x4)
        ])

      affected = %Spell{spell_family: 8, family_flags_0: 0x4}
      unaffected = %Spell{spell_family: 8, family_flags_0: 0x8}

      assert Modifiers.value(entity, affected, :critical_chance, 5.0) == 45.0
      assert Modifiers.value(entity, unaffected, :critical_chance, 5.0) == 5.0
    end

    test "zero masks affect every spell in the same family" do
      entity = entity([modifier_holder(:add_pct_modifier, -100, 14, 0)])
      spell = %Spell{spell_family: 8, family_flags_0: 0x80000000}

      assert Modifiers.integer_value(entity, spell, :cost, 450) == 0
    end

    test "cost modifiers feed the shared power calculation" do
      entity = entity([modifier_holder(:add_pct_modifier, -100, 14, 0)])
      spell = %Spell{spell_family: 8, mana_cost: 450, power_type: 0}

      assert Resources.power_cost(entity, spell) == 0
    end

    test "all-effects modifiers snapshot into periodic aura amounts" do
      entity = entity([modifier_holder(:add_pct_modifier, 50, 8, 0x400)])

      spell = %Spell{
        id: 980,
        spell_family: 8,
        family_flags_0: 0x400,
        duration_ms: 10_000,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :periodic_damage, base_points: 100, amplitude_ms: 2_000}
        ]
      }

      context = CastContext.from_caster(entity, spell, 2)
      target = %{object: %Object{guid: 2}, unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: []}}
      {target, _events} = AuraLogic.apply_spell(target, context, spell, 1_000)

      assert context.effect_damage_multiplier == 1.5
      assert [%Holder{auras: [%Aura{amount: 150}]}] = target.unit.auras
    end

    test "speed modifiers alter movement aura amounts from their DBC operation" do
      entity = entity([modifier_holder(:add_flat_modifier, -20, 12, 0x400000)])

      spell = %Spell{
        id: 18_223,
        spell_family: 8,
        family_flags_0: 0x400000,
        duration_ms: 12_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_decrease_speed, base_points: -10}]
      }

      context = CastContext.from_caster(entity, spell, 2)
      target = %{object: %Object{guid: 2}, unit: %Unit{level: 60, auras: []}}
      {target, _events} = AuraLogic.apply_spell(target, context, spell, 1_000)

      assert [%Holder{auras: [%Aura{amount: -30}]}] = target.unit.auras
    end
  end

  describe "consumable_holder_ids/2" do
    test "selects charged modifiers only when the cast uses their operation" do
      crit = modifier_holder(:add_flat_modifier, 100, 7, 0x4, charges: 1, id: 14_177)
      cast_time = modifier_holder(:add_flat_modifier, -5_500, 10, 0x8, charges: 1, id: 18_708)
      entity = entity([crit, cast_time])

      strike = %Spell{
        spell_family: 8,
        family_flags_0: 0x4,
        dmg_class: 2,
        effects: [%Effect{type: :school_damage}]
      }

      assert Modifiers.consumable_holder_ids(entity, strike) == [14_177]
      assert Modifiers.consumable_holder_ids(entity, %Spell{spell_family: 8, family_flags_0: 0x4}) == []
    end

    test "the aura lifecycle spends a holder charge through its single removal funnel" do
      holder = modifier_holder(:add_flat_modifier, 100, 7, 0x4, charges: 1, id: 14_177)
      entity = entity([%{holder | slot: 0}])

      assert {entity, _events} = AuraLogic.spend_spell_charges(entity, [14_177], 1_000)
      assert entity.unit.auras == []
    end
  end

  defp entity(holders), do: %{object: %Object{guid: 1}, unit: %Unit{level: 60, auras: holders}}

  defp modifier_holder(type, amount, operation, class_mask, opts \\ []) do
    %Holder{
      spell: %Spell{id: Keyword.get(opts, :id, 1), spell_family: 8},
      charges: Keyword.get(opts, :charges),
      auras: [%Aura{type: type, amount: amount, misc_value: operation, class_mask: class_mask}]
    }
  end
end
