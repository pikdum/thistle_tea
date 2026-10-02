defmodule ThistleTea.Game.Core.Aura.PeriodicDamageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Aura.PeriodicDamage
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Test.Unique

  setup [:target]

  describe "amount/4" do
    test "fractional ramps round without bias", %{target: target} do
      for {kind, base, expected} <- [{:agony, 7, 3.5}, {:starshards, 14, 14 * 2 / 3}] do
        spell = spell(kind, base)
        holder = %Holder{spell: spell}
        aura = %Aura{index: 0, type: :periodic_damage, amount: base, tick_count: 1}

        values = for n <- 0..299, do: PeriodicDamage.amount(target, holder, aura, fn -> (n + 0.5) / 300 end)
        assert Enum.all?(values, &(&1 in [floor(expected), ceil(expected)]))
        assert_in_delta Enum.sum(values) / 300, expected, 0.00001
      end
    end

    test "ramps use simple base dice independently of snapshot and level scaling", %{target: target} do
      spell = spell(:starshards)
      effect = %{hd(spell.effects) | die_sides: 100, real_points_per_level: 10.0}
      holder = %Holder{spell: %{spell | effects: [effect]}}
      aura = %Aura{index: 0, type: :periodic_damage, amount: 100, tick_count: 1}
      assert PeriodicDamage.amount(target, holder, aura) == 90
      assert PeriodicDamage.amount(target, holder, %{aura | tick_count: 3}) == 100
      assert PeriodicDamage.amount(target, holder, %{aura | tick_count: 5}) == 110
    end

    test "unrelated families and similarly named spells retain constant damage", %{target: target} do
      for spell <- [
            %{spell(:starshards) | spell_family: 0},
            %{spell(:starshards) | family_flags_0: 0x80000000},
            %{spell(:agony) | spell_family: 0},
            %{spell(:agony) | family_flags_0: 0x10000}
          ],
          tick <- 1..12 do
        aura = %Aura{index: 0, type: :periodic_damage, amount: 30, tick_count: tick}
        assert PeriodicDamage.amount(target, %Holder{spell: spell}, aura) == 30
      end
    end

    test "target bonuses precede rounding and flat reductions cannot remove over half", %{target: target} do
      spell = spell(:starshards, 7)
      holder = %Holder{spell: spell}
      aura = %Aura{index: 0, type: :periodic_damage, amount: 7, tick_count: 1}
      target = with_aura(target, :mod_damage_percent_taken, 50)
      assert PeriodicDamage.amount(target, holder, aura, fn -> 0.99 end) == 7
      target = with_aura(target, :mod_damage_taken, 10)
      assert PeriodicDamage.amount(target, holder, aura, fn -> 0.1 end) == 15
      assert PeriodicDamage.amount(target, holder, aura, fn -> 0.9 end) == 14

      reduced = with_aura(%{target | unit: %{target.unit | auras: []}}, :mod_damage_taken, -1_000)
      assert PeriodicDamage.amount(reduced, holder, %{aura | amount: 60, tick_count: 3}) == 30
    end
  end

  describe "tick/2" do
    test "both ramps preserve caster bonuses through the final tick and expiry", %{target: target} do
      for {kind, expected} <- [
            {:starshards, [50, 50, 60, 60, 70, 70]},
            {:agony, [45, 45, 45, 45, 60, 60, 60, 60, 75, 75, 75, 75]}
          ] do
        spell = spell(kind)

        context = %CastContext{
          caster_guid: 2,
          caster_level: 60,
          spell_damage_bonus: %{arcane: 40},
          damage_done_multiplier: 1.2
        }

        {target, _events} = Aura.apply_spell(target, context, spell, 0)
        assert hd(hd(target.unit.auras).auras).amount == 60

        final =
          expected
          |> Enum.with_index(1)
          |> Enum.reduce(target, fn {damage, tick}, target ->
            {damaged, events} = Aura.tick(target, tick * 1_000)
            assert [%Effects.SpellDamage{damage: ^damage, absorbed: 0, resisted: 0, periodic?: true}] = events
            assert damaged.unit.health == target.unit.health - damage
            assert {^damaged, []} = Aura.tick(damaged, tick * 1_000)
            damaged
          end)

        assert final.unit.auras == []
        assert Aura.next_event_at(final) == nil
        assert {^final, []} = Aura.tick(final, 20_000)
      end
    end

    test "delayed wakeups advance one stage and refresh resets the executed count", %{target: target} do
      spell = spell(:agony)
      {target, _events} = Aura.apply_spell(target, 2, 60, spell, 0)
      {target, [%Effects.SpellDamage{damage: 15}]} = Aura.tick(target, 8_500)
      {target, [%Effects.SpellDamage{damage: 15}]} = Aura.tick(target, 9_000)
      assert hd(hd(target.unit.auras).auras).tick_count == 2
      {target, _events} = Aura.apply_spell(target, 2, 60, spell, 9_500)
      assert hd(hd(target.unit.auras).auras).tick_count == 0
      assert Aura.next_event_at(target) == 10_500
      assert {^target, []} = Aura.tick(target, 10_000)
      {_target, [%Effects.SpellDamage{damage: 15}]} = Aura.tick(target, 10_500)
    end

    test "resistance and absorption consume the modified tick once", %{target: target} do
      target = %{target | unit: %{target.unit | base_arcane_resistance: 300}}
      target = with_aura(target, :mod_damage_percent_taken, 100)
      target = with_aura(target, :school_absorb, 10)
      {target, _events} = Aura.apply_spell(target, 2, 60, spell(:starshards), 0)
      :rand.seed(:exsss, {1, 1, 1})
      {damaged, events} = Aura.tick(target, 1_000)
      assert [%Effects.SpellDamage{damage: damage, absorbed: 10, resisted: resisted}] = events
      assert resisted > 0
      assert damage + resisted == 40
      assert damaged.unit.health == target.unit.health - damage + 10
      refute Enum.any?(damaged.unit.auras, &Enum.any?(&1.auras, fn aura -> aura.type == :school_absorb end))
      assert hd(Enum.find(damaged.unit.auras, &(&1.spell.id == 10_797)).auras).tick_count == 1
    end

    test "removal and death cannot resume an old ramp", %{target: target} do
      spell = spell(:starshards)
      {target, _events} = Aura.apply_spell(target, 2, 60, spell, 0)
      {target, _events} = Aura.tick(target, 1_000)
      {removed, _events} = Aura.remove_spells(target, [spell.id], 1_500)
      dead = Entity.take_damage(target, 10_000, 1_500)

      for stopped <- [removed, dead] do
        assert stopped.unit.auras == []
        assert Aura.next_event_at(stopped) == nil
        assert {^stopped, []} = Aura.tick(stopped, 2_000)
      end
    end
  end

  defp target(_context) do
    %{
      target: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 10_000, max_health: 10_000, level: 60, auras: []},
        internal: %Internal{}
      }
    }
  end

  defp spell(kind, base \\ 30) do
    {id, family, mask, ticks} = if kind == :agony, do: {980, 5, 0x400, 12}, else: {10_797, 6, 0x200000, 6}

    %Spell{
      id: id,
      school: :arcane,
      spell_family: family,
      family_flags_0: mask,
      duration_ms: ticks * 1_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :periodic_damage,
          base_points: base - 1,
          base_dice: 1,
          die_sides: 1,
          amplitude_ms: 1_000,
          bonus_coefficient: 0.5,
          implicit_target_a: :target_enemy
        }
      ]
    }
  end

  defp with_aura(target, type, amount) do
    holder = %Holder{
      spell: %Spell{id: Unique.integer()},
      auras: [%Aura{type: type, amount: amount, misc_value: 64}]
    }

    %{target | unit: %{target.unit | auras: [holder | target.unit.auras]}}
  end
end
