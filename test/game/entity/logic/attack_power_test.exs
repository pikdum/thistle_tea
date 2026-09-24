defmodule ThistleTea.Game.Entity.Logic.AttackPowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:creature]

  describe "recompute/1" do
    test "pets ignore ranged AP modifiers while retaining melee AP buffs", %{mob: mob} do
      auras = [
        holder(:mod_attack_power, 100),
        holder(:mod_ranged_attack_power, 100),
        holder(:mod_ranged_attack_power_pct, 50)
      ]

      for {model, base} <- [hunter_pet: 180, summoned_pet: 180, imp: 90] do
        unit = recompute(%{mob.unit | attack_power_model: model, base_attack_power: base}, auras)
        assert unit.attack_power == base + 100
        assert unit.ranged_attack_power == 0
        assert Stats.recompute(unit) == unit
      end
    end

    test "keeps seed damage and applies melee and ranged modifiers independently", %{mob: mob} do
      assert mob.unit.attack_power == 200
      assert Combat.damage_range(mob) == {100.0, 100.0}
      assert Stats.recompute(mob.unit) == mob.unit

      unit = recompute(mob.unit, [holder(:mod_attack_power, -100), holder(:mod_ranged_attack_power, 100)])
      assert unit.attack_power == 100
      assert unit.ranged_attack_power == 200
      assert_in_delta unit.min_damage, 85.0, 0.0001
      assert_in_delta unit.min_ranged_damage, 65.0, 0.0001
      assert Stats.recompute(unit) == unit
      assert recompute(unit, []) == mob.unit
    end

    test "does not clamp stat deltas before adding them to the creature seed", %{mob: mob} do
      unit = %{mob.unit | class: 8, base_strength: 5, base_agility: 5}
      unit = recompute(unit, [holder(:mod_stat, 10, 0), holder(:mod_stat, 10, 1)])
      assert unit.attack_power == 210
      assert unit.ranged_attack_power == 110
    end

    test "floors damage loss at thirty percent and handles a zero AP seed", %{mob: mob} do
      unit = recompute(mob.unit, [holder(:mod_attack_power, -500)])
      assert unit.attack_power == 0
      assert unit.min_damage == 70.0

      for amount <- [-500, 500] do
        unit = recompute(%{mob.unit | base_attack_power: 0}, [holder(:mod_attack_power, amount)])
        assert unit.min_damage == 100.0
        assert unit.attack_power == max(amount, 0)
        assert Stats.recompute(unit) == unit
      end
    end

    test "uses only changed strength and agility on top of the class-level seed", %{mob: mob} do
      unit = recompute(mob.unit, [holder(:mod_stat, 10, 0), holder(:mod_stat, 20, 1)])
      assert unit.attack_power == 220
      assert unit.ranged_attack_power == 120
      assert_in_delta unit.min_damage, 103.0, 0.0001
      assert unit.max_health == 1_000
      assert recompute(unit, []) == mob.unit
    end

    test "combines stacked flat amounts before independent percentage modifiers", %{mob: mob} do
      flat = %{holder(:mod_attack_power, 10) | stacks: 3}
      percent = %{holder(:mod_attack_power_pct, 10) | stacks: 2}
      other = holder(:mod_attack_power_pct, 50)
      unit = recompute(%{mob.unit | equipment_bonuses: %{attack_power: 20}}, [flat, percent, other])
      assert unit.attack_power == 450
      assert_in_delta unit.min_damage, 137.5, 0.0001
      assert recompute(unit, [other, percent, flat]).attack_power == unit.attack_power
      assert recompute(unit, [holder(:mod_attack_power_pct, -150)]).attack_power == 0
    end

    test "includes ranged equipment and percentage AP in the player weapon formula" do
      unit = %Unit{
        class: 3,
        level: 60,
        base_strength: 100,
        base_agility: 100,
        base_ranged_min_damage: 10.0,
        base_ranged_max_damage: 20.0,
        base_ranged_attack_time: 2_800,
        equipment_bonuses: %{ranged_attack_power: 40},
        auras: [holder(:mod_ranged_attack_power, 50), holder(:mod_ranged_attack_power_pct, 50)]
      }

      unit = Stats.recompute(unit)
      assert unit.ranged_attack_power == 600
      assert unit.attack_power == 300
      assert unit.min_ranged_damage == 130.0
      assert unit.max_ranged_damage == 140.0
      assert Stats.recompute(unit) == unit
    end

    test "preserves creature weapon speed and layers disarm on reduced AP", %{mob: mob} do
      unit = %{mob.unit | virtual_item_info: <<2, 0, 0, 0>>, base_melee_attack_time: 3_000}
      unit = recompute(unit, [holder(:mod_attack_power, -100), holder(:mod_disarm, 0)])
      mob = %{mob | unit: unit}
      assert Combat.attack_speed_ms(mob) == 3_000
      assert Combat.damage_range(mob) == {34.0, 34.0}
    end

    test "uses pet strength formulas and keeps happiness outside the AP ratio", %{mob: mob} do
      unit = %{
        mob.unit
        | attack_power_model: :hunter_pet,
          base_attack_power: 180,
          power5: 700_000,
          max_power5: 1_050_000
      }

      for {amount, expected} <- [{0, 125.0}, {180, 162.5}, {-500, 87.5}] do
        updated = recompute(unit, [holder(:mod_attack_power, amount)])
        assert_in_delta updated.min_damage, expected, 0.0001
        assert Stats.recompute(updated) == updated
      end

      for {model, base} <- [summoned_pet: 180, imp: 90] do
        unit = %{unit | attack_power_model: model, base_attack_power: base, max_power5: 0}
        updated = recompute(unit, [holder(:mod_stat, 10, 0)])
        assert updated.attack_power == if(model == :imp, do: 100, else: 200)
        assert updated.min_damage == 100.0
        updated = recompute(updated, [holder(:mod_stat, 10, 0), holder(:mod_attack_power, -50)])
        expected = if model == :imp, do: 85.0, else: 92.5
        assert_in_delta updated.min_damage, expected, 0.0001
      end
    end
  end

  describe "apply_spell/5" do
    test "refreshes once and restores damage after expiry, removal, death, and reset", %{mob: mob} do
      spell = %Spell{
        id: 1160,
        name: "Demoralizing Shout",
        school: :physical,
        duration_ms: 30_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :mod_attack_power,
            base_points: -100,
            implicit_target_a: :aoe_enemy_at_caster
          }
        ]
      }

      context = %CastContext{caster_guid: 2, caster_level: 60, target_hostile?: true}
      {debuffed, _events} = Aura.apply_spell(mob, context, spell, 0)
      assert [%Holder{negative?: true, slot: 32}] = debuffed.unit.auras
      assert debuffed.unit.attack_power == 100
      assert Combat.damage_range(debuffed) == {85.0, 85.0}
      {refreshed, _events} = Aura.apply_spell(debuffed, context, spell, 10_000)
      assert length(refreshed.unit.auras) == 1
      assert refreshed.unit.attack_power == 100
      {still_active, _events} = Aura.expire_due(refreshed, 30_000)
      assert still_active.unit.attack_power == 100
      {expired, _events} = Aura.expire_due(refreshed, 40_000)
      {removed, _events} = Aura.remove_spells(debuffed, [1160], 100)
      dead = Core.take_damage(debuffed, 1_000, 100)
      reset = Mob.respawn(debuffed)

      for entity <- [expired, removed, dead, reset] do
        assert entity.unit.auras == []
        assert entity.unit.attack_power == 200
        assert Combat.damage_range(entity) == {100.0, 100.0}
      end
    end
  end

  describe "from_caster/3" do
    test "weapon spells use adjusted creature damage without adding player AP damage", %{mob: mob} do
      mob = %{mob | unit: recompute(mob.unit, [holder(:mod_attack_power, -100)])}
      target = %{mob | object: %Object{guid: 2}, unit: %{mob.unit | flags: 0x00040000, normal_resistance: 0, auras: []}}

      for {type, damage_class, expected} <- [
            {:weapon_damage, 2, 85},
            {:normalized_weapon_damage, 2, 85},
            {:weapon_damage, 3, 50}
          ] do
        spell = %Spell{id: 90_001, school: :physical, dmg_class: damage_class, effects: [%Effect{type: type}]}
        context = CastContext.from_caster(mob, spell, 2)
        assert context.attack_power == 100
        assert context.weapon_attack_power_included?
        context = %{context | hit_chance_bonus: 100, melee_crit_chance: 0, caster_position: nil}
        {_target, events} = SpellEffect.receive(target, context, spell, 0)
        assert damage(events) == expected
      end
    end

    test "hunter weapon spells apply happiness once and retain their cast snapshot", %{mob: mob} do
      unit = %{
        mob.unit
        | attack_power_model: :hunter_pet,
          base_attack_power: 180,
          power5: 700_000,
          max_power5: 1_050_000
      }

      mob = %{mob | unit: recompute(unit, [holder(:mod_attack_power, 180)])}
      spell = %Spell{id: 90_001, school: :physical, dmg_class: 2, effects: [%Effect{type: :weapon_damage}]}
      context = CastContext.from_caster(mob, spell, 2)
      assert context.weapon_base_min == 130.0
      assert context.happiness_multiplier == 1.25
      assert_in_delta mob.unit.min_damage, 162.5, 0.0001
      target = %{mob | object: %Object{guid: 2}, unit: %{mob.unit | flags: 0x00040000, normal_resistance: 0, auras: []}}
      context = %{context | hit_chance_bonus: 100, melee_crit_chance: 0, caster_position: nil}
      {_target, events} = SpellEffect.receive(target, context, spell, 0)
      assert damage(events) == 162
      assert recompute(mob.unit, []).min_damage == 125.0
      assert context.weapon_base_min == 130.0
    end
  end

  defp creature(_context) do
    unit = %Unit{
      class: 1,
      level: 60,
      health: 1_000,
      max_health: 1_000,
      base_strength: 100,
      base_agility: 50,
      base_attack_power: 200,
      base_ranged_attack_power: 100,
      base_min_damage: 100.0,
      base_max_damage: 100.0,
      base_ranged_min_damage: 50.0,
      base_ranged_max_damage: 50.0,
      base_melee_attack_time: 2_000,
      base_ranged_attack_time: 2_000,
      auras: []
    }

    unit = Stats.recompute(unit)

    mob = %Mob{
      object: %Object{guid: 1},
      unit: unit,
      internal: %Internal{spawn: %Spawn{unit: unit}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{mob: mob}
  end

  defp holder(type, amount, misc_value \\ 0) do
    %Holder{spell: %Spell{id: 90_000}, auras: [%AuraData{type: type, amount: amount, misc_value: misc_value}]}
  end

  defp recompute(unit, holders), do: Stats.recompute(%{unit | auras: holders})

  defp damage(events) do
    Enum.find_value(events, fn
      %Effects.SpellDamage{damage: damage} -> damage
      _event -> nil
    end)
  end
end
