defmodule ThistleTea.Game.Spell.RadiusTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.Logic.Totems
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Radius
  alias ThistleTea.Game.Spell.Target

  setup [:build_caster]

  describe "target_query/3" do
    test "applies matching flat and percent modifiers across area shapes", %{caster: caster} do
      for {target, query} <- [
            {:aoe_enemy_at_caster, {:caster_aoe, 22.5}},
            {:aoe_enemy_in_cone, {:caster_cone, 22.5}},
            {:aoe_enemy_at_dest, {:targeted_aoe, {1.0, 2.0, 3.0}, 22.5}},
            {:party_around_caster, {:party_aoe, 22.5}},
            {:party_around_target, {:target_party_aoe, 2, 22.5, 0}},
            {:aoe_ally_at_source, {:caster_friendly_aoe, 22.5}},
            {:aoe_ally_at_dest, {:targeted_friendly_aoe, {1.0, 2.0, 3.0}, 22.5}},
            {:raid_and_class, {:party_class_aoe, 2, 22.5}}
          ] do
        spell = spell(%Effect{type: :heal, implicit_target_a: target, radius_yards: 10.0})
        targets = %{Target.at({1.0, 2.0, 3.0}) | selection: {:unit, 2}}
        assert SpellTarget.target_query(spell, targets, Modifiers.snapshot(caster, spell)) == query
      end
    end

    test "does not modify unrelated families, masks, or direct unit targets", %{caster: caster} do
      spell = spell(%Effect{type: :heal, implicit_target_a: :party_around_caster, radius_yards: 10.0})

      for unrelated <- [%{spell | spell_family: 8}, %{spell | family_flags_0: 2}] do
        assert SpellTarget.target_query(unrelated, Target.none(), Modifiers.snapshot(caster, unrelated)) ==
                 {:party_aoe, 10.0}
      end

      direct = %{spell | effects: [%Effect{type: :heal, implicit_target_a: :target_ally}]}
      assert SpellTarget.target_query(direct, Target.unit(2), Modifiers.snapshot(caster, direct)) == {:unit, 2}
      assert Modifiers.consumable_holder_ids(caster, direct) == []
    end
  end

  describe "maximum/3" do
    test "keeps radii nonnegative and handles absent area effects" do
      modifiers = [%Aura{type: :add_flat_modifier, misc_value: 6, amount: -20}]
      assert Radius.maximum([%Effect{radius_yards: 10.0}], modifiers) == 0.0
      assert Radius.maximum([], modifiers, nil) == nil
      assert Radius.effect(%Effect{}, [], 8.0) == 8.0
    end
  end

  describe "apply_spell/4" do
    test "totems snapshot owner modifiers and refresh using their retained radius", %{caster: owner} do
      summon = %{Effects.summon_totem(1, 1, 60_000) | spell_id: 100, health: 5}
      totem = Totems.prepare(%{owner | object: %Object{guid: 2}, unit: %{owner.unit | auras: []}}, owner, summon, 0)
      spell = spell(%Effect{index: 0, type: :apply_area_aura, aura: :mod_stat, radius_yards: 20.0})
      context = CastContext.from_caster(totem, spell, 2)
      {totem, _events} = AuraLogic.apply_spell(totem, context, spell, 0)
      assert [%Holder{area_radius: 37.5, next_area_refresh_at: 1_000}] = totem.unit.auras
      {_totem, events} = AuraLogic.tick(totem, 1_000)
      assert Enum.any?(events, &match?(%Effects.DeliverSpellToQuery{query: {:party_aoe, 37.5}}, &1))

      reset_owner = %{owner | unit: %{owner.unit | auras: []}}
      rebuilt = Totems.prepare(totem, reset_owner, summon, 2_000)
      context = CastContext.from_caster(rebuilt, spell, 2)
      {rebuilt, _events} = AuraLogic.apply_spell(rebuilt, context, spell, 2_000)
      assert [%Holder{area_radius: 20.0}] = rebuilt.unit.auras
    end

    test "remote recipients expire when the source no longer refreshes them", %{caster: caster} do
      spell = spell(%Effect{index: 0, type: :apply_area_aura, aura: :mod_stat, radius_yards: 20.0})
      context = CastContext.from_caster(caster, spell, 2)
      target = %{caster | object: %Object{guid: 2}, unit: %{caster.unit | auras: []}}
      {target, _events} = AuraLogic.apply_spell(target, context, spell, 0)
      assert [%Holder{area_radius: 37.5, next_area_refresh_at: nil, expires_at: 2_500}] = target.unit.auras
      {target, _events} = AuraLogic.tick(target, 2_501)
      assert target.unit.auras == []
    end
  end

  describe "complete/3" do
    test "retains the radius after consuming a modifier charge", %{caster: caster} do
      spell = spell(%Effect{index: 0, type: :persistent_area_aura, aura: :periodic_damage, radius_yards: 10.0})
      casting = %{Cast.new(spell, Target.at({1.0, 2.0, 3.0}), 0) | modifier_holder_ids: [900]}
      caster = %{caster | internal: %{caster.internal | casting: casting}}
      finished = Casting.complete(caster, casting, 0)
      assert finished.unit.auras == []
      assert Enum.any?(finished.internal.events, &match?(%Effects.SpawnAreaEffect{radius_yards: 22.5}, &1))
      assert hd(spell.effects).radius_yards == 10.0
    end
  end

  defp build_caster(_context) do
    holder = %Holder{
      spell: %Spell{id: 900, spell_family: 11},
      charges: 1,
      auras: [
        %Aura{type: :add_flat_modifier, misc_value: 6, amount: 5, class_mask: 1},
        %Aura{type: :add_pct_modifier, misc_value: 6, amount: 50, class_mask: 1}
      ]
    }

    %{
      caster: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 100, auras: [holder]},
        internal: %Internal{}
      }
    }
  end

  defp spell(effect), do: %Spell{id: 100, spell_family: 11, family_flags_0: 1, duration_ms: -1, effects: [effect]}
end
