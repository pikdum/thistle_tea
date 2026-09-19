defmodule ThistleTea.Game.Entity.Logic.ResistancePenetrationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "snapshot/1" do
    test "combines gear and stacked auras without crossing school masks", %{caster: caster} do
      caster = %{
        caster
        | unit: %{
            caster.unit
            | equipment_bonuses: %{resistance_penetration: [{124, -10}]},
              auras: [holder(1, -700, 3), holder(126, -10), holder(4, -30)]
          }
      }

      modifiers = ResistancePenetration.snapshot(caster)
      assert ResistancePenetration.resistance(3_000, modifiers, :physical) == 900
      assert ResistancePenetration.resistance(100, modifiers, :fire) == 50
      assert ResistancePenetration.resistance(100, modifiers, 2) == 50
      assert ResistancePenetration.resistance(100, modifiers, :frost) == 80
      assert ResistancePenetration.resistance(100, modifiers, :holy) == 90
      assert ResistancePenetration.resistance(100, modifiers, %Spell{school: :arcane}) == 80
      assert ResistancePenetration.snapshot(%{}) == []
    end
  end

  describe "resistance/3" do
    test "clamps overpenetration without modifying innate level resistance" do
      resistance = ResistancePenetration.resistance(100, [{126, -1_000}], :fire)
      assert resistance == 0
      assert SpellResist.resist_chance(resistance, 60, true, 3) > 0
      assert SpellResist.resist_chance(resistance, 60, false, 3) == 0
      assert ResistancePenetration.resistance(nil, [], :physical) == 0
      assert ResistancePenetration.resistance(100, [{0, -100}, {4, 20}], :fire) == 120
    end
  end

  describe "resolve/4" do
    test "applies armor penetration before normal, critical, and off-hand damage", %{caster: caster, target: target} do
      caster = %{caster | unit: %{caster.unit | auras: [holder(1, -700, 3), holder(126, -1_000)]}}
      attack = AttackTable.attacker_context(caster)

      for offhand? <- [false, true] do
        attack = Map.put(attack, :offhand?, offhand?)
        result = AttackTable.resolve(target, %{attack | crit_chance: 0}, 1_000, roll: 9_999)
        assert result.damage == AttackTable.armor_reduced_damage(1_000, 900, 60)
        result = AttackTable.resolve(target, %{attack | crit_chance: 100}, 1_000, roll: 9_999)
        assert result.damage == AttackTable.armor_reduced_damage(1_000, 900, 60) * 2
      end

      assert target.unit.normal_resistance == 3_000

      plain =
        AttackTable.resolve(target, AttackTable.attacker_context(caster) |> Map.put(:resistance_penetration, []), 1_000,
          roll: 9_999
        )

      assert plain.damage == AttackTable.armor_reduced_damage(1_000, 3_000, 60)
    end
  end

  describe "apply_weapon_group/4" do
    test "melee and ranged weapon abilities use the caster's penetration", %{caster: caster, target: target} do
      caster = %{caster | unit: %{caster.unit | auras: [holder(1, -700)]}}

      for damage_class <- [2, 3] do
        spell = %Spell{id: 90_001, school: :physical, dmg_class: damage_class, effects: [%Effect{type: :weapon_damage}]}

        context = %{
          CastContext.from_caster(caster, spell, 2)
          | weapon_base_min: 1_000,
            weapon_base_max: 1_000,
            attack_power: 0
        }

        {damaged, events} = DamageHeal.apply_weapon_group(target, context, spell, 0)
        expected = AttackTable.armor_reduced_damage(1_000, 2_300, 60)
        assert damaged.unit.health == target.unit.health - expected
        assert damage(events).damage == expected
        assert damaged.unit.normal_resistance == 3_000
      end
    end
  end

  describe "apply_damage_amount/6" do
    test "penetrates only the spell's school and reports partial resistance", %{caster: caster, target: target} do
      caster = %{caster | unit: %{caster.unit | auras: [holder(4, -300), holder(1, -3_000)]}}

      for school <- [:fire, :frost] do
        spell = %Spell{id: 90_001, school: school, dmg_class: 1}
        context = %{CastContext.from_caster(caster, spell, 2) | spell_crit_chance: 0}
        seed()
        expected = SpellResist.resisted_amount(1_000, if(school == :fire, do: 0, else: 300), 60)
        seed()
        {damaged, events} = DamageHeal.apply_damage_amount(target, context, spell, 1_000, 0)
        assert damage(events).resisted == expected
        assert damage(events).damage == 1_000 - expected
        assert damaged.unit.health == target.unit.health - 1_000 + expected
        assert damaged.unit.frost_resistance == 300
        if school == :frost, do: assert(expected > 0)
      end
    end
  end

  describe "tick/2" do
    test "periodic damage and leech preserve penetration through refresh and caster cleanup", %{
      caster: caster,
      target: target
    } do
      {buffed, _events} = Aura.apply_spell(caster, 1, 60, bonus_spell(), 0)
      {unbuffed, _events} = Aura.remove_spells(buffed, [90_002], 100)

      for type <- [:periodic_damage, :periodic_leech] do
        spell = periodic_spell(type)
        context = CastContext.from_caster(buffed, spell, 2)
        {affected, _events} = Aura.apply_spell(target, context, spell, 0)
        {ticked, events} = Aura.tick(affected, 1_000)
        assert ticked.unit.health == target.unit.health - 1_000
        assert damage(events).damage == 1_000
        assert damage(events).resisted == 0
        if type == :periodic_leech, do: assert(Enum.any?(events, &match?(%Effects.HealEntity{amount: 1_000}, &1)))
        assert ResistancePenetration.snapshot(unbuffed) == []
        {refreshed, _events} = Aura.apply_spell(ticked, CastContext.from_caster(unbuffed, spell, 2), spell, 1_000)
        assert hd(refreshed.unit.auras).resistance_penetration == []
        {expired, _events} = Aura.tick(refreshed, 4_000)
        assert expired.unit.auras == []
      end
    end

    test "uses the target's current resistance at each tick", %{caster: caster, target: target} do
      spell = periodic_spell(:periodic_damage)
      caster = %{caster | unit: %{caster.unit | auras: [holder(4, -300)]}}
      {affected, _events} = Aura.apply_spell(target, CastContext.from_caster(caster, spell, 2), spell, 0)
      affected = %{affected | unit: %{affected.unit | fire_resistance: 600}}
      seed()
      expected = SpellResist.resisted_amount(1_000, 300, 60, dot?: true)
      assert expected > 0
      seed()
      {ticked, events} = Aura.tick(affected, 1_000)
      assert damage(events).resisted == expected
      assert ticked.unit.health == target.unit.health - 1_000 + expected
    end
  end

  describe "apply_spell/5" do
    test "cancellation, expiry, and death clear future attack and spell snapshots", %{caster: caster} do
      {buffed, _events} = Aura.apply_spell(caster, 1, 60, bonus_spell(), 0)
      saved = CastContext.from_caster(buffed, %Spell{school: :fire}, 2)
      {cancelled, _events} = Aura.remove_spells(buffed, [90_002], 500)
      {expired, _events} = Aura.tick(buffed, 1_000)
      dead = Core.take_damage(buffed, 10_000, 500)

      for entity <- [cancelled, expired, dead] do
        assert CastContext.from_caster(entity, %Spell{}, 2).resistance_penetration == []
        assert AttackTable.attacker_context(entity).resistance_penetration == []
      end

      assert saved.resistance_penetration == [{4, -300}]
    end
  end

  defp entities(_context) do
    unit = %Unit{health: 10_000, max_health: 10_000, level: 60, class: 1, auras: []}

    caster = %Character{
      object: %Object{guid: 1},
      unit: unit,
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %Mob{
      object: %Object{guid: 2},
      unit: %{
        unit
        | normal_resistance: 3_000,
          base_normal_resistance: 3_000,
          fire_resistance: 300,
          base_fire_resistance: 300,
          frost_resistance: 300,
          base_frost_resistance: 300,
          flags: 0x00040000
      },
      internal: %Internal{}
    }

    %{caster: caster, target: target}
  end

  defp holder(mask, amount, stacks \\ 1) do
    %Holder{
      spell: %Spell{id: 90_000},
      caster_guid: 1,
      stacks: stacks,
      auras: [%AuraData{type: :mod_target_resistance, amount: amount, misc_value: mask}]
    }
  end

  defp bonus_spell do
    %Spell{
      id: 90_002,
      duration_ms: 1_000,
      effects: [%Effect{type: :apply_aura, aura: :mod_target_resistance, base_points: -300, misc_value: 4}]
    }
  end

  defp periodic_spell(type) do
    %Spell{
      id: 90_003,
      school: :fire,
      dmg_class: 1,
      duration_ms: 3_000,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: type, base_points: 1_000, amplitude_ms: 1_000, multiple_value: 1.0}
      ]
    }
  end

  defp seed, do: :rand.seed(:exsss, {110, 2, 3})
  defp damage(events), do: Enum.find(events, &match?(%Effects.SpellDamage{}, &1))
end
