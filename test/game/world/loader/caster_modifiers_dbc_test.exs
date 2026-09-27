defmodule ThistleTea.Game.World.Loader.CasterModifiersDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:target]

  describe "load/1" do
    test "flagged direct spells ignore caster power, percentages, and criticals", %{target: target} do
      for id <- [3585, 3587, 18_150, 27_820, 28_062, 28_085, 28_375] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :ignore_caster_modifiers)
        :rand.seed(:exsss, {1, 2, 3})
        {baseline, events} = SpellEffect.receive(target, context(), spell, 0)
        [hit] = Enum.filter(events, &is_struct(&1, Effects.SpellDamage))
        refute hit.crit?
        :rand.seed(:exsss, {1, 2, 3})
        {boosted, events} = SpellEffect.receive(target, boosted_context(), spell, 0)
        assert [^hit] = Enum.filter(events, &is_struct(&1, Effects.SpellDamage))
        assert boosted.unit.health == baseline.unit.health
      end
    end

    test "flagged periodic effects retain their base snapshots and expiry", %{target: target} do
      for id <- [13_493, 28_622, 28_801] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :ignore_caster_modifiers)
        :rand.seed(:exsss, {1, 2, 3})
        {baseline, _events} = Aura.apply_spell(target, context(), spell, 0)
        :rand.seed(:exsss, {1, 2, 3})
        {boosted, _events} = Aura.apply_spell(target, boosted_context(), spell, 0)
        assert hd(boosted.unit.auras).auras == hd(baseline.unit.auras).auras
        assert hd(boosted.unit.auras).expires_at == hd(baseline.unit.auras).expires_at
      end
    end

    test "ordinary Smite still gains caster bonuses", %{target: target} do
      spell = SpellLoader.load(585)
      refute Spell.attribute?(spell, :ignore_caster_modifiers)
      :rand.seed(:exsss, {1, 2, 3})
      {_baseline, [%Effects.SpellDamage{damage: base, crit?: false}]} = SpellEffect.receive(target, context(), spell, 0)
      :rand.seed(:exsss, {1, 2, 3})

      {_boosted, [%Effects.SpellDamage{damage: damage, crit?: true}]} =
        SpellEffect.receive(target, boosted_context(), spell, 0)

      assert damage > base * 2
    end
  end

  defp target(_context) do
    %{
      target: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 10_000, max_health: 10_000, auras: []},
        internal: %Internal{}
      }
    }
  end

  defp context, do: %CastContext{caster_guid: 2, caster_level: 60}

  defp boosted_context do
    %{
      context()
      | spell_damage_bonus: %{physical: 100, holy: 100, fire: 100, nature: 100, frost: 100, shadow: 100, arcane: 100},
        spell_crit_chance: 100,
        damage_done_multiplier: 2.0,
        spell_modifiers: [%AuraData{type: :add_pct_modifier, misc_value: 0, amount: 100}],
        happiness_multiplier: 1.25,
        damage_done_versus: [{64, 100}],
        target_damage: [{64, 100}],
        spell_damage_versus: [{64, 100}]
    }
  end
end
