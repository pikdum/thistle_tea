defmodule ThistleTea.Game.Entity.Logic.DamageFeedbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "receive/4" do
    test "direct spells and weapon abilities report modified damage and absorption", %{entity: entity} do
      for {modifier, damage} <- [{-50, 50}, {50, 150}, {-100, 0}],
          type <- [:school_damage, :weapon_damage],
          class <- [1, 2, 3] do
        entity = protect(entity, modifier)
        spell = damage_spell(type, class)

        context = %CastContext{
          caster_guid: 2,
          caster_level: 60,
          hit_chance_bonus: 100,
          melee_crit_chance: 0,
          spell_crit_chance: 0,
          weapon_base_min: 0,
          weapon_base_max: 0
        }

        {entity, events} = SpellEffect.receive(entity, context, spell, 0)
        absorbed = min(30, damage)
        assert entity.unit.health == 1_000 - damage + absorbed
        assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: ^damage, absorbed: ^absorbed}, &1))
      end
    end

    test "overkill reports the hit amount and god mode reports no damage", %{entity: entity} do
      spell = damage_spell(:school_damage, 1)
      context = %CastContext{caster_guid: 2, caster_level: 60, hit_outcome: :hit}
      low_health = %{entity | unit: %{entity.unit | health: 10}}
      {dead, events} = SpellEffect.receive(low_health, context, spell, 0)
      assert dead.unit.health == 0
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 100}, &1))
      immortal = %{entity | internal: %{entity.internal | godmode: true}}
      {immortal, events} = SpellEffect.receive(immortal, context, spell, 0)
      assert immortal.unit.health == 1_000
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 0}, &1))
    end
  end

  describe "receive_attack/4" do
    test "melee and ranged autoattacks report modified health damage", %{entity: entity} do
      for {modifier, damage} <- [{-50, 20}, {50, 120}, {-100, 0}], ranged? <- [false, true] do
        entity = protect(entity, modifier)
        attack = %{caster: 2, caster_level: 60, damage: 100, ranged?: ranged?}
        {entity, events} = Combat.receive_attack(entity, attack, 0, roll: 9_999)
        assert entity.unit.health == 1_000 - damage
        assert Enum.any?(events, &match?(%Effects.AttackerStateUpdate{damage: ^damage}, &1))
      end
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, flags: 0x00040000, auras: []},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp damage_spell(type, class) do
    %Spell{
      id: 1,
      school: :physical,
      dmg_class: class,
      effects: [%Effect{index: 0, type: type, base_points: 100}]
    }
  end

  defp protect(entity, modifier) do
    holders = [
      %Holder{
        spell: %Spell{id: 2},
        auras: [%Aura{index: 0, type: :mod_damage_percent_taken, amount: modifier, misc_value: 1}]
      },
      %Holder{
        spell: %Spell{id: 3},
        auras: [%Aura{index: 0, type: :school_absorb, amount: 30, misc_value: 1}]
      }
    ]

    %{entity | unit: %{entity.unit | auras: holders}}
  end
end
