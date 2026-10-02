defmodule ThistleTea.Game.Core.Combat.DamageReceivedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat
  alias ThistleTea.Game.Core.Combat.AttackTable
  alias ThistleTea.Game.Core.Combat.DamageReceived
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Test.Unique

  setup [:target]

  describe "spell_amount/6" do
    test "weapon ticks scale both school and attack flats before independent percentages", %{target: target} do
      target =
        target
        |> with_aura(:mod_damage_taken, 20)
        |> with_aura(:mod_melee_damage_taken, 30)
        |> with_aura(:mod_ranged_damage_taken, 50)
        |> with_aura(:mod_melee_damage_taken_pct, -50)
        |> with_aura(:mod_damage_percent_taken, 100)

      for {class, expected} <- [{1, 240}, {2, 150}, {3, 340}] do
        spell = spell(class)
        assert DamageReceived.spell_amount(target, 100, spell, hd(spell.effects), :dot, 2) == expected
      end
    end

    test "magic reductions cap at half while attack reductions may suppress the whole hit", %{target: target} do
      target = with_aura(target, :mod_damage_taken, -1_000)

      for {class, expected} <- [{0, 50}, {1, 50}, {2, 0}, {3, 0}] do
        spell = spell(class)
        assert DamageReceived.spell_amount(target, 100, spell, hd(spell.effects)) == expected
      end
    end

    test "flat bonuses obey school masks and fixed-damage coefficients", %{target: target} do
      target = target |> with_aura(:mod_damage_taken, 40) |> with_aura(:mod_damage_percent_taken, 50)
      spell = spell(1)
      assert DamageReceived.spell_amount(target, 100, spell, hd(spell.effects)) == 180
      assert DamageReceived.spell_amount(target, 100, %{spell | school: :frost}, hd(spell.effects)) == 100
      assert DamageReceived.spell_amount(target, 100, %{spell | custom_flags: 0x10}, hd(spell.effects)) == 150
    end

    test "zero weapon damage cannot acquire a flat damage bonus", %{target: target} do
      target = with_aura(target, :mod_damage_taken, 40)
      spell = spell(2)
      assert DamageReceived.spell_amount(target, 0, spell, hd(spell.effects)) == 0
    end
  end

  describe "receive/4" do
    test "physical spells apply target bonuses and critical damage before armor", %{target: target} do
      target = target |> with_aura(:mod_damage_taken, 40, 1) |> with_aura(:mod_damage_percent_taken, 50, 1)
      target = %{target | unit: %{target.unit | normal_resistance: 3_000, flags: 0x00040000}}

      for class <- [1, 2], ignore_armor? <- [false, true] do
        spell = %{spell(class) | school: :physical, custom_flags: if(ignore_armor?, do: 0x20, else: 0)}
        context = %{context() | spell_crit_chance: 100, melee_crit_chance: 100, hit_chance_bonus: 100}
        unmitigated = if class == 1, do: 270, else: 360
        expected = if ignore_armor?, do: unmitigated, else: AttackTable.armor_reduced_damage(unmitigated, 3_000, 60)
        {damaged, events} = SpellEffect.receive(target, context, spell, 0)

        assert [%Effects.SpellDamage{damage: ^expected, crit?: true}] =
                 Enum.filter(events, &is_struct(&1, Effects.SpellDamage))

        assert damaged.unit.health == 10_000 - expected
      end
    end

    test "target bonuses precede critical hits and absorbed damage agrees with health loss", %{target: target} do
      target =
        target
        |> with_aura(:mod_damage_taken, 40)
        |> with_aura(:mod_damage_percent_taken, 50)
        |> with_aura(:school_absorb, 50)

      spell = spell(1)
      context = %{context() | spell_crit_chance: 100}
      {damaged, events} = SpellEffect.receive(target, context, spell, 0)
      assert [%Effects.SpellDamage{damage: 270, absorbed: 50, resisted: 0, crit?: true}] = events
      assert damaged.unit.health == 9_780
      refute Enum.any?(damaged.unit.auras, &Enum.any?(&1.auras, fn aura -> aura.type == :school_absorb end))
    end

    test "bypass spells retain resistance and absorption while ignoring target bonuses", %{target: target} do
      for class <- [0, 1, 2, 3], type <- [:school_damage, :apply_aura] do
        target =
          target
          |> with_aura(:mod_damage_taken, 1_000)
          |> with_aura(:mod_damage_percent_taken, 100)
          |> with_aura(:mod_melee_damage_taken, 1_000)
          |> with_aura(:mod_ranged_damage_taken, 1_000)
          |> with_aura(:mod_melee_damage_taken_pct, 100)
          |> with_aura(:mod_ranged_damage_taken_pct, 100)
          |> with_aura(:school_absorb, 20)

        target = %{target | unit: %{target.unit | base_fire_resistance: 300, fire_resistance: 300}}
        spell = %{spell(class, type) | attributes: MapSet.new([:ignore_damage_taken_modifiers])}
        :rand.seed(:exsss, {1, 1, 1})
        {damaged, events} = SpellEffect.receive(target, context(), spell, 0)
        {damaged, events} = if type == :apply_aura, do: Aura.tick(damaged, 1_000), else: {damaged, events}
        [event] = Enum.filter(events, &is_struct(&1, Effects.SpellDamage))
        assert event.resisted > 0
        assert event.damage + event.resisted == 100
        assert event.absorbed == 20
        assert damaged.unit.health == 10_000 - event.damage + 20
      end
    end

    test "power burns use the original effect coefficient for received bonuses", %{target: target} do
      target = target |> with_aura(:mod_damage_taken, 20) |> with_aura(:mod_damage_percent_taken, 100)

      for type <- [:power_burn, :apply_aura] do
        spell = spell(1, type)
        effect = %{hd(spell.effects) | base_points: 40, multiple_value: 0.5, misc_value: 0, aura: :periodic_power_burn}
        spell = %{spell | effects: [effect]}
        {damaged, events} = SpellEffect.receive(target, context(), spell, 0)
        {damaged, events} = if type == :apply_aura, do: Aura.tick(damaged, 1_000), else: {damaged, events}
        assert [%Effects.SpellDamage{damage: 60}] = events
        assert damaged.unit.power1 == 60
        assert damaged.unit.health == 9_940
      end
    end
  end

  describe "receive_attack/4" do
    test "school percentages apply before block and are not applied twice", %{target: target} do
      target = with_aura(target, :mod_damage_percent_taken, 100, 1)
      attack = %{caster: 2, caster_level: 60, caster_player?: true, damage: 100}
      {damaged, events} = Combat.receive_attack(target, attack, 0, roll: 2_500)
      [event] = Enum.filter(events, &is_struct(&1, Effects.AttackerStateUpdate))
      assert event.damage == 170
      assert damaged.unit.health == 9_830
    end
  end

  defp target(_context) do
    %{
      target: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          health: 10_000,
          max_health: 10_000,
          level: 60,
          power_type: 0,
          power1: 100,
          max_power1: 100,
          auras: []
        },
        internal: %Internal{}
      }
    }
  end

  defp context, do: %CastContext{caster_guid: 2, caster_level: 60, spell_crit_chance: 0, melee_crit?: false}

  defp spell(class, type \\ :school_damage) do
    %Spell{
      id: 90_001,
      dmg_class: class,
      school: :fire,
      duration_ms: 3_000,
      effects: [
        %Effect{
          index: 0,
          type: type,
          aura: :periodic_damage,
          base_points: 100,
          amplitude_ms: 1_000,
          bonus_coefficient: 0.5
        }
      ]
    }
  end

  defp with_aura(target, type, amount, school \\ 4) do
    holder = %Holder{
      spell: %Spell{id: Unique.integer()},
      auras: [%Aura{type: type, amount: amount, misc_value: school}]
    }

    %{target | unit: %{target.unit | auras: [holder | target.unit.auras]}}
  end
end
