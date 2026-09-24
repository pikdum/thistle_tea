defmodule ThistleTea.Game.Spell.ChainTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Chain
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers

  setup [:build_caster]

  describe "plan/4" do
    test "attenuates each effect independently and preserves primary-only effects", %{caster: caster} do
      spell = %Spell{
        effects: [
          effect(0, 3, 0.7),
          effect(1, 2, 0.5),
          %{effect(2, 0, 1.0) | implicit_target_a: :caster}
        ]
      }

      plan = Chain.plan(caster, spell, [2, 3, 4, 1], [2, 3, 4, 1])
      assert plan[1] == %{2 => 1.0}
      assert plan[2] == %{0 => 1.0, 1 => 1.0}
      assert plan[3] == %{0 => 0.7, 1 => 0.5}
      assert_in_delta plan[4][0], 0.49, 0.0001
      refute Map.has_key?(plan[4], 1)

      secondary = %CastContext{target_guid: 4} |> Chain.put_context(plan)
      assert Enum.map(Chain.effects(spell.effects, secondary), & &1.index) == [0]
    end

    test "missed recipients count toward target limits but do not advance attenuation", %{caster: caster} do
      spell = %Spell{effects: [effect(0, 3, 0.5)]}
      plan = Chain.plan(caster, spell, [2, 3, 4], [3, 4])
      assert plan == %{2 => %{0 => 1.0}, 3 => %{0 => 1.0}, 4 => %{0 => 0.5}}
    end

    test "ordinary spells and unrelated DBC multipliers remain unchanged", %{caster: caster} do
      spell = %Spell{effects: [effect(0, 0, 0.2)]}
      assert Chain.plan(caster, spell, [2], [2]) == nil
      assert Chain.scale(100, hd(spell.effects), %CastContext{}) == 100
    end

    test "snapshots jump count and later-effect modifiers with charge eligibility", %{caster: caster} do
      spell = %Spell{id: 421, spell_family: 11, family_flags_0: 2, effects: [effect(0, 3, 0.5)]}

      holder = %Holder{
        spell: %Spell{id: 900, spell_family: 11},
        charges: 1,
        auras: [
          %Aura{type: :add_flat_modifier, misc_value: 17, class_mask: 2, amount: 1},
          %Aura{type: :add_pct_modifier, misc_value: 20, class_mask: 2, amount: 20}
        ]
      }

      caster = %{caster | unit: %{caster.unit | auras: [holder]}}
      assert Chain.count(caster, spell) == 4
      assert Modifiers.consumable_holder_ids(caster, spell) == [900]
      plan = Chain.plan(caster, spell, [2, 3, 4, 5], [2, 3, 4, 5])
      assert_in_delta plan[5][0], 0.216, 0.0001
    end
  end

  describe "scale/3" do
    test "scales damage before spell power and retains target health and feedback", %{caster: caster} do
      spell = %Spell{id: 421, school: :nature, dmg_class: 0, effects: [effect(0, 3, 0.7)]}
      plan = Chain.plan(caster, spell, [2, 3, 4], [2, 3, 4])
      context = %CastContext{caster_guid: 1, caster_level: 60, spell_damage_bonus: %{nature: 40}}

      for {guid, damage} <- [{2, 240}, {3, 180}, {4, 137}] do
        target = %{caster | object: %Object{guid: guid}}
        context = %{context | target_guid: guid} |> Chain.put_context(plan)
        {target, events} = SpellEffect.receive(target, context, spell, 1_000)
        assert target.unit.health == 1_000 - damage
        assert Enum.any?(events, &match?(%{damage: ^damage, target_guid: ^guid}, &1))
      end
    end

    test "scales healing before healing power including a jump back to the caster", %{caster: caster} do
      effect = %{effect(0, 3, 0.5) | type: :heal, implicit_target_a: :chain_heal}
      spell = %Spell{id: 1064, school: :nature, effects: [effect]}
      plan = Chain.plan(caster, spell, [2, 3, 1], [2, 3, 1])
      context = %CastContext{caster_guid: 1, caster_level: 60, healing_bonus: 40}

      for {guid, healing} <- [{2, 240}, {3, 140}, {1, 90}] do
        target = %{caster | object: %Object{guid: guid}, unit: %{caster.unit | health: 100}}
        context = %{context | target_guid: guid} |> Chain.put_context(plan)
        {target, _events} = SpellEffect.receive(target, context, spell, 1_000)
        assert target.unit.health == 100 + healing
      end
    end
  end

  defp effect(index, count, multiplier) do
    %Effect{
      index: index,
      type: :school_damage,
      implicit_target_a: :target_enemy,
      chain_targets: count,
      damage_multiplier: multiplier,
      base_points: 200,
      die_sides: 0,
      bonus_coefficient: 1.0
    }
  end

  defp build_caster(_context) do
    %{
      caster: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, auras: []},
        internal: %Internal{}
      }
    }
  end
end
