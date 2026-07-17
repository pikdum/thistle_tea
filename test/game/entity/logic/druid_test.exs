defmodule ThistleTea.Game.Entity.Logic.DruidTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Druid
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

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
      assert Enum.any?(events, &match?(%Event{type: :drain_power, target_guid: 5, misc_value: 3}, &1))
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
      refute Enum.any?(events, &(&1.type == :drain_power))
    end
  end

  describe "Enrage" do
    test "uses the VMangos custom aura amount for each bear form" do
      spell = %Spell{script_name: "spell_druid_enrage"}

      bear = %Character{object: %Object{guid: 5}, unit: %Unit{level: 60, shapeshift_form: 5}}
      dire_bear = %{bear | unit: %{bear.unit | shapeshift_form: 8}}

      assert %Event{type: :trigger_spell, spell_id: 25_503, slot: 1, amount: -27} =
               Druid.enrage_event(bear, spell)

      assert %Event{type: :trigger_spell, spell_id: 25_503, slot: 1, amount: -16} =
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
