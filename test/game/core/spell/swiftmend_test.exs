defmodule ThistleTea.Game.Core.Spell.SwiftmendTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.CastValidation
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target

  setup [:entities]

  describe "validate/6" do
    test "requires an eligible HoT for explicit and implicit self casts", %{caster: caster, spell: spell} do
      for {targets, info} <- [{Target.unit(1), :self}, {Target.none(), nil}] do
        assert {:error, :target_aurastate} = CastValidation.validate(caster, spell, targets, info, 1_000)

        for flags <- [0x10, 0x40] do
          caster = %{caster | unit: %{caster.unit | auras: [hot(774, flags, 100, 8_000)]}}
          assert :ok = CastValidation.validate(caster, spell, targets, info, 1_000)
        end
      end
    end

    test "uses the recipient aura sources regardless of the HoT caster", %{caster: caster, spell: spell} do
      target = %{guid: 2, alive?: true, hostile?: false, friendly?: true, helpful?: true}
      assert {:error, :target_aurastate} = CastValidation.validate(caster, spell, Target.unit(2), target, 1_000)

      for flags <- [0x10, 0x40], owner <- [1, 3] do
        target = Map.put(target, :aura_sources, MapSet.new([{774, 7, flags, 0, owner}]))
        assert :ok = CastValidation.validate(caster, spell, Target.unit(2), target, 1_000)
      end

      caster = %{caster | unit: %{caster.unit | auras: [hot(774, 0x10, 100, 8_000)]}}
      sources = MapSet.new([{139, 6, 0x10, 0, 1}, {774, 7, 0x20, 0, 1}])
      target = Map.put(target, :aura_sources, sources)
      assert {:error, :target_aurastate} = CastValidation.validate(caster, spell, Target.unit(2), target, 1_000)
    end

    test "ordinary heals have no HoT requirement", %{caster: caster, spell: spell} do
      assert :ok = CastValidation.validate(caster, %{spell | script_name: nil}, Target.none(), nil, 1_000)
    end
  end

  describe "receive/4" do
    test "a missing or expired HoT cannot become a base or bonus heal", context do
      for holders <- [[], [hot(774, 0x10, 100, 999)], [hot(774, 0x10, 100, 1_000)]] do
        recipient = %{context.caster | unit: %{context.caster.unit | auras: holders}}
        {unchanged, events} = SpellEffect.receive(recipient, context.cast, context.spell, 1_000)
        assert unchanged.unit.health == recipient.unit.health
        assert unchanged.unit.auras == holders
        refute Enum.any?(events, &is_struct(&1, Effects.SpellHeal))
        refute Enum.any?(events, &is_struct(&1, Effects.HealThreat))
      end
    end

    test "consumes the shortest live HoT and retains other ranks and spells", context do
      expired = hot(774, 0x10, 1_000, 999)
      rejuvenation = hot(1058, 0x10, 100, 8_000)
      regrowth = hot(8936, 0x40, 80, 4_000)
      recipient = %{context.caster | unit: %{context.caster.unit | auras: [expired, rejuvenation, regrowth]}}
      {healed, events} = SpellEffect.receive(recipient, context.cast, context.spell, 1_000)
      assert healed.unit.health == 100 + 80 * 6 + 1
      assert Aura.has_spell?(healed, 1058)
      refute Aura.has_spell?(healed, 8936)
      assert Enum.any?(events, &match?(%Effects.SpellHeal{damage: 481}, &1))
    end

    test "uses four Rejuvenation ticks even near its deadline and preserves critical healing", context do
      recipient = %{context.caster | unit: %{context.caster.unit | auras: [hot(774, 0x10, 100, 1_001)]}}
      cast = %{context.cast | spell_crit_chance: 100.0}
      {healed, events} = SpellEffect.receive(recipient, cast, context.spell, 1_000)
      assert healed.unit.health == 701
      refute Aura.has_spell?(healed, 774)
      assert Enum.any?(events, &match?(%Effects.SpellHeal{damage: 601, crit?: true}, &1))
    end
  end

  defp entities(_context) do
    spell = %Spell{
      id: 18_562,
      script_name: "spell_druid_swiftmend",
      effects: [
        %Effect{
          index: 0,
          type: :heal,
          implicit_target_a: :target_ally,
          base_points: 0,
          base_dice: 1,
          die_sides: 1,
          bonus_coefficient: 0.0
        }
      ]
    }

    %{
      spell: spell,
      caster: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 2_000, level: 60, auras: []},
        player: %Player{},
        internal: %Internal{}
      },
      cast: %CastContext{caster_guid: 3, caster_level: 60, target_guid: 1, healing_bonus: 500}
    }
  end

  defp hot(id, flags, amount, expires_at) do
    %Holder{
      spell: %Spell{id: id, spell_family: 7, family_flags_0: flags},
      caster_guid: 9,
      applied_at: 0,
      expires_at: expires_at,
      auras: [%Aura{index: 0, type: :periodic_heal, amount: amount}]
    }
  end
end
