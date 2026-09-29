defmodule ThistleTea.Game.Core.Class.DruidTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Class.Druid
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect

  describe "consume_swiftmend_hot/3" do
    test "consumes the shortest eligible HoT and converts its remaining spell into healing" do
      rejuvenation = hot(774, 0x10, 100, 8_000)
      regrowth = hot(8936, 0x40, 80, 12_000)
      entity = %Character{unit: %Unit{auras: [regrowth, rejuvenation]}, internal: %Internal{}}
      swiftmend = %Spell{script_name: "spell_druid_swiftmend", spell_family: 7, family_flags_1: 0x2}

      {entity, healing, _events} = Druid.consume_swiftmend_hot(entity, swiftmend, 1_000)

      assert healing == 400
      assert Enum.map(entity.unit.auras, & &1.spell.id) == [8936]
    end
  end

  describe "Faerie Fire" do
    test "its DBC dispel immunity prevents stealth auras" do
      faerie_fire = %Holder{
        spell: %Spell{id: 770},
        caster_guid: 9,
        auras: [%Aura{type: :dispel_immunity, misc_value: 5}]
      }

      prowl = %Spell{
        id: 5215,
        dispel_type: 5,
        effects: [%Effect{type: :apply_aura, aura: :mod_stealth}]
      }

      character = %Character{
        object: %Object{guid: 5},
        unit: %Unit{auras: [faerie_fire]},
        internal: %Internal{}
      }

      {character, events} =
        SpellEffect.receive(character, %CastContext{caster_guid: 5, target_role: :caster}, prowl, 1_000)

      assert character.unit.auras == [faerie_fire]
      assert events == []
    end
  end

  describe "Ferocious Bite" do
    test "converts attack power and remaining energy into damage before draining energy" do
      spell = ferocious_bite()

      context = %CastContext{
        caster_guid: 5,
        caster_level: 60,
        caster_type: :player,
        target_guid: 9,
        spell: spell,
        attack_power: 200,
        combo_points: 5,
        caster_power: 65,
        attack_skill: 300,
        melee_crit_chance: 0.0
      }

      {target, events} = SpellEffect.receive(melee_target(), context, spell, 1_000)

      assert target.unit.health == 708
      assert Enum.any?(events, &match?(%Effects.DrainPower{target_guid: 5, misc_value: 3}, &1))
    end

    test "requires the VMangos script label" do
      spell = %{ferocious_bite() | script_name: nil}

      context = %CastContext{
        caster_guid: 5,
        caster_level: 60,
        caster_type: :player,
        target_guid: 9,
        spell: spell,
        attack_power: 200,
        combo_points: 5,
        caster_power: 65,
        attack_skill: 300,
        melee_crit_chance: 0.0
      }

      {target, events} = SpellEffect.receive(melee_target(), context, spell, 1_000)

      assert target.unit.health == 900
      refute Enum.any?(events, &is_struct(&1, Effects.DrainPower))
    end
  end

  describe "Enrage" do
    test "uses the VMangos custom aura amount for each bear form" do
      spell = %Spell{script_name: "spell_druid_enrage"}

      bear = %Character{object: %Object{guid: 5}, unit: %Unit{level: 60, shapeshift_form: 5}}
      dire_bear = %{bear | unit: %{bear.unit | shapeshift_form: 8}}

      assert %Effects.TriggerSpell{spell_id: 25_503, slot: 1, amount: -27} =
               Druid.enrage_event(bear, spell)

      assert %Effects.TriggerSpell{spell_id: 25_503, slot: 1, amount: -16} =
               Druid.enrage_event(dire_bear, spell)
    end

    test "requires the VMangos script label" do
      bear = %Character{object: %Object{guid: 5}, unit: %Unit{level: 60, shapeshift_form: 5}}

      assert Druid.enrage_event(bear, %Spell{}) == nil
    end
  end

  defp hot(id, family_flags, amount, expires_at) do
    %Holder{
      spell: %Spell{id: id, spell_family: 7, family_flags_0: family_flags},
      caster_guid: 1,
      slot: rem(id, 32),
      expires_at: expires_at,
      auras: [%Aura{type: :periodic_heal, amount: amount}]
    }
  end

  defp ferocious_bite do
    %Spell{
      id: 22_568,
      script_name: "spell_druid_ferocious_bite",
      school: :physical,
      dmg_class: 2,
      attributes: MapSet.new([:ability, :finishing_move]),
      effects: [
        %Effect{
          index: 0,
          type: :school_damage,
          base_points: 100,
          die_sides: 0,
          points_per_combo: 0.0,
          damage_multiplier: 2.5
        }
      ]
    }
  end

  defp melee_target do
    %Mob{
      object: %Object{guid: 9},
      unit: %Unit{
        health: 1_000,
        max_health: 1_000,
        level: 60,
        normal_resistance: 0,
        flags: 0x00040000,
        stand_state: 1,
        auras: []
      },
      internal: %Internal{}
    }
  end
end
