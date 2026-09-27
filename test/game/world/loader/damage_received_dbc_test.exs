defmodule ThistleTea.Game.World.Loader.DamageReceivedDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:target]

  describe "load/1" do
    test "Dampen and Amplify Magic ranks scale with Smite and stop affecting it on removal", %{target: target} do
      attack = SpellLoader.load(585)
      effect = hd(attack.effects)
      coefficient = Coefficient.value(attack, effect, :direct)
      assert coefficient > 0 and coefficient < 1
      context = %CastContext{caster_guid: 2, caster_level: 60}

      for id <- [604, 8450, 8451, 10_173, 10_174, 1008, 8455, 10_169, 10_170] do
        {buffed, _events} = Aura.apply_spell(target, 1, 60, SpellLoader.load(id), 0)
        modifier = Aura.flat_modifier(buffed, :mod_damage_taken, Spell.school_mask(attack))
        assert modifier != 0
        :rand.seed(:exsss, {1, 2, 3})
        {_baseline, [%Effects.SpellDamage{damage: base}]} = SpellEffect.receive(target, context, attack, 1_000)
        :rand.seed(:exsss, {1, 2, 3})
        {damaged, [%Effects.SpellDamage{damage: damage}]} = SpellEffect.receive(buffed, context, attack, 1_000)
        expected = base + max(modifier * coefficient, -base / 2)
        assert damage in [floor(expected), ceil(expected)]
        assert damaged.unit.health == target.unit.health - damage
        {removed, _events} = Aura.remove_spells(buffed, [id], 2_000)
        :rand.seed(:exsss, {1, 2, 3})
        {_target, [%Effects.SpellDamage{damage: ^base}]} = SpellEffect.receive(removed, context, attack, 3_000)
      end
    end

    test "Decimate bypasses target damage bonuses while retaining absorption", %{target: target} do
      spell = SpellLoader.load(28_375)
      assert Spell.attribute?(spell, :ignore_damage_taken_modifiers)

      target = %{
        target
        | unit: %{
            target.unit
            | auras: [
                %Holder{
                  spell: %Spell{id: 90_001},
                  auras: [%AuraData{type: :mod_damage_taken, amount: 100, misc_value: 127}]
                },
                %Holder{
                  spell: %Spell{id: 90_002},
                  auras: [%AuraData{type: :mod_damage_percent_taken, amount: 100, misc_value: 127}]
                },
                %Holder{
                  spell: %Spell{id: 90_003},
                  auras: [%AuraData{type: :school_absorb, amount: 20, misc_value: 127}]
                }
              ]
          }
      }

      {damaged, events} =
        DamageHeal.apply_damage_amount(target, %CastContext{caster_guid: 2, caster_level: 60}, spell, 100, 0,
          damage_effect: hd(spell.effects)
        )

      assert [%Effects.SpellDamage{damage: 100, absorbed: 20}] = events
      assert damaged.unit.health == 9_920
    end
  end

  defp target(_context) do
    %{
      target: %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 10_000, max_health: 10_000, auras: []},
        internal: %Internal{}
      }
    }
  end
end
