defmodule ThistleTea.Game.Entity.Logic.AttackSpeedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.AttackSpeed
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  setup [:unit]

  describe "recompute/1" do
    test "Barkskin slows both hands by 25 percent", %{unit: unit} do
      slowed = %{unit | auras: [holder(:mod_melee_haste, -25, true)]} |> Stats.recompute()
      assert slowed.base_attack_time == 2_500
      assert slowed.offhand_attack_time == 1_875
      assert slowed.ranged_attack_time == 3_000
      assert Combat.attack_speed_ms(%{unit: slowed}) == 2_500
      assert Combat.offhand_attack_speed_ms(%{unit: slowed}) == 1_875
      assert Stats.recompute(slowed) == slowed
      assert Stats.recompute(%{slowed | auras: []}) == Stats.recompute(unit)
    end

    test "independent haste effects multiply", %{unit: unit} do
      hasted = %{unit | auras: [holder(:mod_melee_haste, 20), holder(:mod_melee_haste, 30)]} |> Stats.recompute()
      assert hasted.base_attack_time == trunc(2_000 / 1.2 / 1.3)
      assert hasted.offhand_attack_time == trunc(1_500 / 1.2 / 1.3)
      assert hasted.ranged_attack_time == 3_000
    end

    test "strongest ordinary slow coexists with passive penalties", %{unit: unit} do
      auras = [holder(:mod_melee_haste, -10), holder(:mod_melee_haste, -20), holder(:mod_melee_haste, -25, true)]
      slowed = Stats.recompute(%{unit | auras: auras})
      assert slowed.base_attack_time == 3_000
      assert slowed.offhand_attack_time == 2_250
      weaker = Stats.recompute(%{slowed | auras: [hd(auras), List.last(auras)]})
      assert weaker.base_attack_time == 2_750
    end

    test "general attack speed affects ranged while melee haste does not", %{unit: unit} do
      general = Stats.recompute(%{unit | auras: [holder(:mod_attack_speed, -20)]})
      assert general.base_attack_time == 2_400
      assert general.offhand_attack_time == 1_800
      assert general.ranged_attack_time == 3_600
      ranged = Stats.recompute(%{unit | auras: [holder(:mod_ranged_haste, -20)]})
      assert ranged.base_attack_time == 2_000
      assert ranged.ranged_attack_time == 3_600
    end

    test "haste never changes weapon damage or spell attack-power scaling", %{unit: unit} do
      base = Stats.recompute(unit)
      hasted = Stats.recompute(%{base | auras: [holder(:mod_attack_speed, 50)]})
      assert hasted.min_damage == base.min_damage
      assert hasted.max_damage == base.max_damage
      assert hasted.min_offhand_damage == base.min_offhand_damage
      assert hasted.min_ranged_damage == base.min_ranged_damage
      assert Stats.recompute(hasted) == hasted

      melee = %Spell{id: 1, dmg_class: 2, effects: [%Spell.Effect{type: :weapon_damage}]}
      ranged = %{melee | dmg_class: 3}
      caster = %{object: %{guid: 1}, unit: hasted}
      assert CastContext.from_caster(caster, melee, 2).attack_time_ms == 2_000
      assert CastContext.from_caster(caster, ranged, 2).attack_time_ms == 3_000
    end

    test "gear changes under haste recompute from the new inputs", %{unit: unit} do
      hasted = Stats.recompute(%{unit | auras: [holder(:mod_melee_haste, 100)]})
      changed = Stats.recompute(%{hasted | base_melee_attack_time: 3_400, base_offhand_attack_time: 2_000})
      assert changed.base_attack_time == 1_700
      assert changed.offhand_attack_time == 1_000
      assert Stats.recompute(changed) == changed
      assert Stats.recompute(%{changed | auras: []}).base_attack_time == 3_400
    end

    test "quivers and ranged auras multiply without reducing shot damage", %{unit: unit} do
      base = Stats.recompute(unit)

      hasted =
        Stats.recompute(%{unit | equipment_bonuses: %{ranged_ammo_haste: 15}, auras: [holder(:mod_ranged_haste, 40)]})

      assert hasted.ranged_attack_time == trunc(3_000 / 1.15 / 1.4)
      assert hasted.min_ranged_damage == base.min_ranged_damage
    end

    test "ammunition haste follows bow, gun, thrown, wand, and unequipped transitions", %{unit: unit} do
      quiver = %{unit | equipment_bonuses: %{ranged_ammo_haste: 15}}
      aura = %{unit | auras: [holder(:mod_ranged_ammo_haste, 15)]}

      for source <- [quiver, aura] do
        for {weapon, expected} <- [
              {%ItemTemplate{ammo_type: 2, subclass: 2}, 2_608},
              {%ItemTemplate{ammo_type: 3, subclass: 3}, 2_608},
              {%ItemTemplate{ammo_type: 4, subclass: 16}, 2_608},
              {%ItemTemplate{ammo_type: 0, subclass: 19}, 3_000},
              {nil, 3_000}
            ] do
          changed = Stats.recompute(%{source | ranged_weapon: weapon})
          assert changed.ranged_attack_time == expected
          assert changed.base_ranged_attack_time == 3_000
          assert Stats.recompute(changed) == changed
          assert Stats.recompute(%{changed | ranged_weapon: unit.ranged_weapon}).ranged_attack_time == 2_608
        end
      end

      creature = %{aura | base_attack_power: 100}
      assert Stats.recompute(creature).ranged_attack_time == 3_000
    end

    test "ordinary ranged haste still affects ammunition-free weapons", %{unit: unit} do
      unit = %{
        unit
        | ranged_weapon: %ItemTemplate{ammo_type: 0, subclass: 19},
          equipment_bonuses: %{ranged_ammo_haste: 15, ranged_haste: 20},
          auras: [holder(:mod_ranged_haste, 25), holder(:mod_ranged_ammo_haste, 15)]
      }

      assert Stats.recompute(unit).ranged_attack_time == 2_000
    end

    test "forms use their own base period before haste", %{unit: unit} do
      for {form, base} <- [{1, 1_000}, {5, 2_500}, {8, 2_500}] do
        shifted = Stats.recompute(%{unit | class: 11, shapeshift_form: form, auras: [holder(:mod_melee_haste, 100)]})
        assert shifted.base_attack_time == div(base, 2)
        assert AttackSpeed.base_ms(shifted, :mainhand) == base
      end
    end

    test "missing base inputs leave projected periods untouched" do
      unit = %Unit{base_attack_time: 2_345, auras: [holder(:mod_melee_haste, 100)]}
      assert AttackSpeed.recompute(unit) == unit
    end
  end

  defp unit(_context) do
    %{
      unit: %Unit{
        level: 60,
        class: 1,
        attack_power: 140,
        ranged_attack_power: 140,
        base_melee_attack_time: 2_000,
        base_offhand_attack_time: 1_500,
        base_ranged_attack_time: 3_000,
        ranged_weapon: %ItemTemplate{ammo_type: 2, subclass: 2},
        base_min_damage: 10.0,
        base_max_damage: 20.0,
        base_offhand_min_damage: 5.0,
        base_offhand_max_damage: 10.0,
        base_ranged_min_damage: 20.0,
        base_ranged_max_damage: 30.0,
        auras: []
      }
    }
  end

  defp holder(type, amount, passive \\ false) do
    %Holder{
      spell: %Spell{id: 1, attributes: MapSet.new(if(passive, do: [:passive], else: []))},
      auras: [%Aura{type: type, amount: amount}]
    }
  end
end
