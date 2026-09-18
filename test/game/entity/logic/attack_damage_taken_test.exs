defmodule ThistleTea.Game.Entity.Logic.AttackDamageTakenTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackDamageTaken
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entity]

  describe "amount/4" do
    test "separates attack types and sums stacked flat bonuses", %{entity: entity} do
      entity = with_auras(entity, [holder(:mod_melee_damage_taken, -10, 2), holder(:mod_ranged_damage_taken, 30)])
      assert AttackDamageTaken.amount(entity, 100, :melee) == 80
      assert AttackDamageTaken.amount(entity, 100, :ranged) == 130
      assert AttackDamageTaken.amount(entity, 0, :ranged) == 0
      assert AttackDamageTaken.amount(entity, 10, :melee) == 0
    end

    test "multiplies independent percentages after flat bonuses without school masks", %{entity: entity} do
      entity =
        with_auras(entity, [
          holder(:mod_melee_damage_taken, -20),
          holder(:mod_melee_damage_taken_pct, -10, 2),
          holder(:mod_melee_damage_taken_pct, 50),
          holder(:mod_ranged_damage_taken_pct, -100)
        ])

      assert AttackDamageTaken.amount(entity, 120, :melee) == 120
      assert AttackDamageTaken.amount(entity, 120, :ranged) == 0
    end
  end

  describe "receive_attack/4" do
    test "reduces damage before armor and critical hits with matching feedback", %{entity: entity} do
      entity = with_auras(entity, [holder(:mod_melee_damage_taken, -30)])
      entity = %{entity | unit: %{entity.unit | normal_resistance: 3_000}}
      expected = AttackTable.armor_reduced_damage(70, 3_000, 60) * 2

      {damaged, events} =
        Combat.receive_attack(entity, %{caster: 2, caster_level: 60, damage: 100, crit_chance: 100}, 0, roll: 9_999)

      assert damaged.unit.health == 1_000 - expected
      assert Enum.any?(events, &match?(%Effects.AttackerStateUpdate{damage: ^expected}, &1))
    end

    test "does not reintroduce damage on fully suppressed hits", %{entity: entity} do
      entity = with_auras(entity, [holder(:mod_melee_damage_taken, -100)])

      for attack <- [%{}, %{crit_chance: 100}, %{always_crush?: true}, %{caster_player?: true, caster_level: 57}] do
        {damaged, events} =
          Combat.receive_attack(entity, Map.merge(%{caster: 2, caster_level: 60, damage: 10}, attack), 0, roll: 9_999)

        assert damaged.unit.health == 1_000
        assert Enum.any?(events, &match?(%Effects.AttackerStateUpdate{damage: 0}, &1))
      end

      assert AttackTable.resolve(entity, %{caster_player?: true, caster_level: 57}, 10, roll: 3_000).damage == 0
      assert AttackTable.armor_reduced_damage(0, 3_000, 60) == 0
    end

    test "selects ranged bonuses for ranged attacks and leaves misses unchanged", %{entity: entity} do
      entity = with_auras(entity, [holder(:mod_melee_damage_taken, -100), holder(:mod_ranged_damage_taken, -20)])
      assert AttackTable.resolve(entity, %{caster_level: 60, ranged?: true}, 100, roll: 9_999).damage == 80
      assert AttackTable.resolve(entity, %{caster_level: 60, ranged?: true}, 100, roll: 0).damage == 0
    end
  end

  describe "receive/4" do
    test "weapon abilities use the full flat bonus for their attack class", %{entity: entity} do
      entity = with_auras(entity, [holder(:mod_melee_damage_taken, -30), holder(:mod_ranged_damage_taken, -10)])

      for {class, expected} <- [{2, 70}, {3, 90}] do
        spell = damage_spell(class, :weapon_damage)
        context = context(spell)
        {damaged, events} = SpellEffect.receive(entity, context, spell, 0)
        assert damaged.unit.health == 1_000 - expected
        assert damage(events) == expected
      end
    end

    test "nonweapon effects scale flat bonuses by their coefficient and ignore magic", %{entity: entity} do
      entity = with_auras(entity, [holder(:mod_melee_damage_taken, -40), holder(:mod_ranged_damage_taken, -20)])

      for {class, expected} <- [{2, 80}, {3, 90}, {1, 100}] do
        spell = damage_spell(class, :school_damage)
        {damaged, events} = SpellEffect.receive(entity, context(spell), spell, 0)
        assert damaged.unit.health == 1_000 - expected
        assert damage(events) == expected
      end
    end

    test "reduction precedes absorption and can fully suppress weapon damage", %{entity: entity} do
      absorb = holder(:school_absorb, 20)
      absorb = %{absorb | auras: [%AuraData{type: :school_absorb, amount: 20, misc_value: 127}]}
      entity = with_auras(entity, [holder(:mod_melee_damage_taken, -30), absorb])
      spell = damage_spell(2, :weapon_damage)
      {damaged, events} = SpellEffect.receive(entity, context(spell), spell, 0)
      assert damaged.unit.health == 950
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 70, absorbed: 20}, &1))
      entity = with_auras(entity, [holder(:mod_melee_damage_taken, -200)])
      {damaged, events} = SpellEffect.receive(entity, context(spell), spell, 0)
      assert damaged.unit.health == 1_000
      assert damage(events) == 0
    end
  end

  describe "tick/2" do
    test "uses live reductions for physical ability ticks and preserves the snapshot", %{entity: entity} do
      spell = %Spell{
        id: 91_000,
        school: :physical,
        dmg_class: 2,
        duration_ms: 4_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :periodic_damage,
            base_points: 100,
            amplitude_ms: 1_000,
            bonus_coefficient: 0.5
          }
        ]
      }

      {entity, _} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {entity, _} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 900
      reduction = holder(:mod_melee_damage_taken, -40)
      entity = with_auras(entity, [reduction | entity.unit.auras])
      {entity, events} = Aura.tick(entity, 2_000)
      assert entity.unit.health == 820
      assert damage(events) == 80
      assert hd(Enum.find(entity.unit.auras, &(&1.spell.id == spell.id)).auras).amount == 100
      {entity, _} = Aura.remove_spells(entity, [reduction.spell.id], 2_500)
      {entity, events} = Aura.tick(entity, 3_000)
      assert entity.unit.health == 720
      assert damage(events) == 100
    end
  end

  describe "apply_spell/5" do
    test "refresh, removal, expiry and death never retain reduction", %{entity: entity} do
      spell = %Spell{
        id: 92_000,
        duration_ms: 1_000,
        effects: [%Effect{type: :apply_aura, aura: :mod_melee_damage_taken, base_points: -30}]
      }

      {buffed, _} = Aura.apply_spell(entity, 1, 60, spell, 0)
      {refreshed, _} = Aura.apply_spell(buffed, 1, 60, spell, 500)
      assert AttackDamageTaken.amount(refreshed, 100, :melee) == 70
      {active, _} = Aura.tick(refreshed, 1_000)
      assert AttackDamageTaken.amount(active, 100, :melee) == 70
      {expired, _} = Aura.tick(active, 1_500)
      {removed, _} = Aura.remove_spells(refreshed, [spell.id], 600)
      dead = Core.take_damage(refreshed, 1_000, 600)

      for cleaned <- [expired, removed, dead] do
        assert AttackDamageTaken.amount(cleaned, 100, :melee) == 100
      end
    end
  end

  defp entity(_) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, flags: 0x00040000, auras: []},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp holder(type, amount, stacks \\ 1) do
    %Holder{
      spell: %Spell{id: :erlang.phash2({type, amount})},
      caster_guid: 1,
      stacks: stacks,
      auras: [%AuraData{type: type, amount: amount}]
    }
  end

  defp with_auras(entity, auras), do: %{entity | unit: %{entity.unit | auras: auras}}

  defp damage_spell(class, type) do
    %Spell{
      id: 90_000,
      school: :physical,
      dmg_class: class,
      effects: [%Effect{index: 0, type: type, base_points: 100, bonus_coefficient: 0.5}]
    }
  end

  defp context(spell) do
    %CastContext{
      caster_guid: 2,
      caster_level: 60,
      spell: spell,
      hit_chance_bonus: 100,
      weapon_base_min: 0,
      weapon_base_max: 0,
      melee_crit_chance: 0,
      spell_crit_chance: 0
    }
  end

  defp damage(events), do: events |> Enum.find(&match?(%Effects.SpellDamage{}, &1)) |> Map.fetch!(:damage)
end
