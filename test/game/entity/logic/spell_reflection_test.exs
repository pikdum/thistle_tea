defmodule ThistleTea.Game.Entity.Logic.SpellReflectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.WorldRef

  setup [:reflection_target]

  describe "reflect_spell?/3" do
    test "combines general reflection with matching school chances", %{target: target} do
      target = put_holders(target, [holder(1, 3), holder(2, 20, :fire)])
      assert Aura.reflect_spell?(target, damage_spell(:fire), fn -> 23 end)
      refute Aura.reflect_spell?(target, damage_spell(:fire), fn -> 24 end)
      assert Aura.reflect_spell?(target, damage_spell(:frost), fn -> 3 end)
      refute Aura.reflect_spell?(target, damage_spell(:frost), fn -> 4 end)
    end

    test "zero chance never reflects and guaranteed reflection needs no roll", %{target: target} do
      refute Aura.reflect_spell?(put_holders(target, []), damage_spell(), fn -> flunk("unexpected roll") end)
      assert Aura.reflect_spell?(target, damage_spell(), fn -> flunk("unexpected roll") end)
    end
  end

  describe "receive/4" do
    test "reflection precedes the saved resist outcome", %{target: target, context: context} do
      context = %{context | hit_outcome: :resist}
      target = put_holders(target, [charged_holder(1)])
      {target, events} = SpellEffect.receive(target, context, damage_spell(), 100)
      assert target.unit.auras == []
      assert target.unit.health == 100
      assert [%Effects.SpellLogMiss{reason: :reflect}, %Effects.DeliverSpell{cast_context: returned}] = events
      assert returned.hit_outcome == :hit

      {target, [%Effects.SpellLogMiss{reason: :resist}]} = SpellEffect.receive(target, context, damage_spell(), 200)
      assert target.unit.health == 100
    end

    test "reflects magic damage from every school with caster attribution", %{target: target, context: context} do
      for school <- [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane] do
        spell = damage_spell(school)
        {result, events} = SpellEffect.receive(target, context, spell, 100)
        assert result.unit.health == 100
        assert [%Effects.SpellLogMiss{reason: :reflect}, %Effects.DeliverSpell{cast_context: reflected}] = events
        assert reflected.caster_guid == 2
        assert reflected.reflected_by_guid == 1
        assert reflected.target_guid == 2

        caster = %{target | object: %Object{guid: 2}}
        {caster, [%Effects.SpellDamage{damage: 20}]} = SpellEffect.receive(caster, reflected, spell, 100)
        assert caster.unit.health == 80
      end
    end

    test "does not reflect abilities or spells with reflection bypass attributes", %{target: target, context: context} do
      for attribute <- [:ability, :no_reflection, :no_immunities, :passive] do
        spell = %{damage_spell() | attributes: MapSet.new([attribute])}
        {result, events} = SpellEffect.receive(target, context, spell, 100)
        assert result.unit.health == 80
        refute Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :reflect}, &1))
      end
    end

    test "requires the magic damage class", %{target: target, context: context} do
      for damage_class <- [0, 2, 3] do
        spell = %{damage_spell() | dmg_class: damage_class}
        {_result, events} = SpellEffect.receive(target, context, spell, 100)
        refute Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :reflect}, &1))
      end
    end

    test "does not reflect healing, self casts, or already reflected spells", %{target: target, context: context} do
      heal = %{damage_spell() | effects: [%Effect{index: 0, type: :heal, base_points: 20}]}
      {_target, events} = SpellEffect.receive(target, context, heal, 100)
      assert [%Effects.SpellHeal{}] = events

      for context <- [%{context | caster_guid: 1}, %{context | reflected_by_guid: 3}] do
        {_target, events} = SpellEffect.receive(target, context, damage_spell(), 100)
        refute Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :reflect}, &1))
      end
    end

    test "immunity takes precedence without consuming reflection", %{target: target, context: context} do
      immune = %Holder{spell: %Spell{id: 50}, auras: [%AuraData{type: :damage_immunity, misc_value: 4}]}
      target = put_holders(target, [charged_holder(2), immune])
      {target, [%Effects.SpellLogMiss{reason: :immune}]} = SpellEffect.receive(target, context, damage_spell(), 100)
      assert hd(target.unit.auras).charges == 2
    end

    test "consumes one charge per reflected cast and removes the exhausted holder", %{target: target, context: context} do
      target = put_holders(target, [charged_holder(2)])

      spell = %{
        damage_spell()
        | effects: damage_spell().effects ++ [%Effect{index: 1, type: :school_damage, base_points: 10}]
      }

      {target, _events} = SpellEffect.receive(target, context, spell, 100)
      assert [%Holder{charges: 1}] = target.unit.auras
      assert target.internal.broadcast_update?
      assert target.unit.health == 100
      {target, _events} = SpellEffect.receive(target, context, spell, 200)
      assert target.unit.auras == []
      assert target.unit.aura == 0
      {target, _events} = SpellEffect.receive(target, context, spell, 300)
      assert target.unit.health == 70
    end

    test "preserves unmatched school charges and unrelated holders", %{target: target, context: context} do
      frost = %{charged_holder(2) | spell: %{charged_holder(2).spell | id: 51}, auras: holder(51, 100, :frost).auras}
      target = put_holders(target, [charged_holder(1), frost, holder(52, 3)])
      {target, _events} = SpellEffect.receive(target, context, damage_spell(), 100)
      assert Enum.map(target.unit.auras, & &1.spell.id) == [51, 52]
      assert hd(target.unit.auras).charges == 2
      refute Aura.reflect_spell?(target, damage_spell(), fn -> 4 end)
    end

    test "does not consume a charge on an unreflectable hit", %{target: target, context: context} do
      target = put_holders(target, [charged_holder(1)])
      spell = %{damage_spell() | attributes: MapSet.new([:no_reflection])}
      {target, _events} = SpellEffect.receive(target, context, spell, 100)
      assert target.unit.health == 80
      assert [%Holder{charges: 1}] = target.unit.auras
    end

    test "removal, expiry, and death clear reflection", %{target: target} do
      target = put_holders(target, [%{holder(10, 100) | expires_at: 200}])
      {expired, _events} = Aura.expire_due(target, 200)
      {removed, _events} = Aura.remove_spells(target, [10], 100)
      dead = Core.take_damage(target, 100, 100)

      for result <- [expired, removed, dead] do
        refute Aura.reflect_spell?(result, damage_spell(), fn -> 1 end)
        assert result.unit.auras == []
      end
    end
  end

  defp reflection_target(_context) do
    target = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 10, auras: [holder(10, 100)]},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{target: target, context: %CastContext{caster_guid: 2, caster_level: 10, target_role: :other}}
  end

  defp holder(id, amount, school \\ nil) do
    %Holder{
      spell: %Spell{id: id},
      caster_guid: 1,
      auras: [
        %AuraData{
          type: if(school, do: :reflect_spells_school, else: :reflect_spells),
          amount: amount,
          misc_value: if(school, do: Spell.school_mask(school), else: 0)
        }
      ]
    }
  end

  defp charged_holder(charges) do
    holder = holder(30_003, 100)

    %{
      holder
      | charges: charges,
        spell: %{holder.spell | proc_type_mask: 0x20000, proc_chance: 100, proc_rule: %ProcRule{proc_ex: 0x800}}
    }
  end

  defp put_holders(target, holders), do: %{target | unit: %{target.unit | auras: holders}}

  defp damage_spell(school \\ :fire) do
    %Spell{
      id: 133,
      school: school,
      dmg_class: 1,
      effects: [%Effect{index: 0, type: :school_damage, base_points: 20, implicit_target_a: :target_enemy}]
    }
  end
end
