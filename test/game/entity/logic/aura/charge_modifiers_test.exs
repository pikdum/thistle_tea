defmodule ThistleTea.Game.Entity.Logic.Aura.ChargeModifiersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Aura.Application
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "apply_spell/4" do
    test "captures caster charge modifiers and projects the resulting count", %{caster: caster} do
      spell = spell()
      context = CastContext.from_caster(caster, spell, 2)
      {target, _events} = AuraLogic.apply_spell(target(), context, spell, 1_000)
      assert [%Holder{charges: 2, slot: slot}] = target.unit.auras
      assert :binary.at(target.unit.aura_applications, slot) == 1
    end

    test "applies flat modifiers before percentages and truncates fractional charges", %{caster: caster} do
      [flat] = caster.unit.auras

      percent = %{
        flat
        | spell: %{flat.spell | id: 51},
          auras: [%Aura{type: :add_pct_modifier, misc_value: 4, amount: 25, class_mask: 1}]
      }

      caster = put_in(caster.unit.auras, [flat, percent])
      spell = %{spell() | proc_charges: 2}
      {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell, 2), spell, 0)
      assert [%Holder{charges: 3}] = target.unit.auras
    end

    test "ignores recipient modifiers and family or mask mismatches", %{caster: caster} do
      for spell <- [%{spell() | spell_family: 3}, %{spell() | family_flags_0: 2}] do
        {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell, 2), spell, 0)
        assert [%Holder{charges: 1}] = target.unit.auras
      end

      context = CastContext.from_caster(target(), spell(), 1)
      {target, _events} = AuraLogic.apply_spell(caster, context, spell(), 0)
      assert Enum.find(target.unit.auras, &(&1.spell.id == 100)).charges == 1
    end

    test "zero charges remain unlimited unless a modifier supplies charges", %{caster: caster} do
      spell = %{spell() | proc_charges: 0}
      {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(target(), spell, 2), spell, 0)
      assert [%Holder{charges: nil}] = target.unit.auras
      {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell, 2), spell, 0)
      assert [%Holder{charges: 1}] = target.unit.auras
    end

    test "nonpositive modified counts remain unlimited", %{caster: caster} do
      [modifier] = caster.unit.auras

      for amount <- [-1, -10] do
        modifier = %{modifier | auras: Enum.map(modifier.auras, &%{&1 | amount: amount})}
        caster = put_in(caster.unit.auras, [modifier])
        {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell(), 2), spell(), 0)
        assert [%Holder{charges: nil}] = target.unit.auras
      end
    end

    test "refresh resets spent charges using the new cast snapshot", %{caster: caster} do
      context = CastContext.from_caster(caster, spell(), 2)
      {target, _events} = AuraLogic.apply_spell(target(), context, spell(), 0)
      {target, _events} = AuraLogic.spend_spell_charges(target, [100], 1_000)
      assert [%Holder{charges: 1}] = target.unit.auras
      {target, _events} = AuraLogic.apply_spell(target, context, spell(), 2_000)
      assert [%Holder{charges: 2, expires_at: 7_000}] = target.unit.auras
      context = CastContext.from_caster(target(), spell(), 2)
      {target, _events} = AuraLogic.apply_spell(target, context, spell(), 3_000)
      assert [%Holder{charges: 1, expires_at: 8_000}] = target.unit.auras
    end
  end

  describe "linked_holder/4" do
    test "self-owned linked auras use the owner's charge modifiers", %{caster: caster} do
      assert %Holder{charges: 2, linked_from: {50, 1}} = Application.linked_holder(caster, spell(), {50, 1}, 0)
    end
  end

  describe "complete/2" do
    test "spends a charged modifier after capturing the new aura's charges", %{caster: caster} do
      caster = put_in(caster.unit.auras, [%{hd(caster.unit.auras) | charges: 1}])
      assert Modifiers.consumable_holder_ids(caster, spell()) == [50]
      assert Modifiers.consumable_holder_ids(caster, %{spell() | effects: [%Effect{type: :school_damage}]}) == []
      completed = caster |> Casting.start(spell(), Target.self(1), 1_000) |> Casting.complete(1_000)
      assert [%Holder{spell: %Spell{id: 100}, charges: 2}] = completed.unit.auras
    end
  end

  defp caster(_context) do
    modifier = %Holder{
      spell: %Spell{id: 50, spell_family: 4},
      auras: [%Aura{type: :add_flat_modifier, misc_value: 4, amount: 1, class_mask: 1}]
    }

    target = target()
    %{caster: %{target | object: %Object{guid: 1}, unit: %{target.unit | auras: [modifier]}}}
  end

  defp target do
    %Mob{
      object: %Object{guid: 2},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0},
      internal: %Internal{world: WorldRef.open(451)}
    }
  end

  defp spell do
    %Spell{
      id: 100,
      spell_family: 4,
      family_flags_0: 1,
      duration_ms: 5_000,
      proc_charges: 1,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_block_percent, base_points: 75, implicit_target_a: :caster}
      ]
    }
  end
end
