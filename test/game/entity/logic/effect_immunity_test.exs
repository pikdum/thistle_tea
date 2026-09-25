defmodule ThistleTea.Game.Entity.Logic.EffectImmunityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.EffectImmunity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "receive/4" do
    test "state immunity blocks control without a mechanic and reports immune", %{entity: entity} do
      entity = protect(entity, :state_immunity, :mod_stun)
      {updated, events} = SpellEffect.receive(entity, 2, stun(), 100)

      refute Aura.has_aura?(updated, :mod_stun)
      assert [%Effects.SpellLogMiss{reason: :immune}] = events
    end

    test "a mixed spell still deals damage while its stun is blocked", %{entity: entity} do
      entity = protect(entity, :state_immunity, :mod_stun)
      spell = %{stun() | effects: [%Effect{index: 1, type: :school_damage, base_points: 10} | stun().effects]}
      {updated, events} = SpellEffect.receive(entity, 2, spell, 100)

      assert updated.unit.health == 90
      refute Aura.has_aura?(updated, :mod_stun)
      assert Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
      refute Enum.any?(events, &match?(%Effects.SpellLogMiss{}, &1))
    end

    test "effect immunity blocks damage but retains an unrelated aura", %{entity: entity} do
      entity = protect(entity, :effect_immunity, :school_damage)
      spell = %{stun() | effects: [%Effect{index: 1, type: :school_damage, base_points: 10} | stun().effects]}
      {updated, events} = SpellEffect.receive(entity, 2, spell, 100)

      assert updated.unit.health == 100
      assert Aura.has_aura?(updated, :mod_stun)
      refute Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
    end

    test "all matching effects return one immune result", %{entity: entity} do
      entity = protect(entity, :effect_immunity, :apply_aura)
      {updated, events} = SpellEffect.receive(entity, 2, stun(), 100)

      refute Aura.has_aura?(updated, :mod_stun)
      assert [%Effects.SpellLogMiss{reason: :immune}] = events
    end

    test "restriction-ignoring spells bypass immunity", %{entity: entity} do
      entity = protect(entity, :state_immunity, :mod_stun)
      spell = %{stun() | attributes: MapSet.new([:ignore_caster_and_target_restrictions])}
      {updated, _events} = SpellEffect.receive(entity, 2, spell, 100)
      assert Aura.has_aura?(updated, :mod_stun)
    end

    test "full immunity takes precedence over a melee avoidance roll", %{entity: entity} do
      entity = protect(entity, :state_immunity, :mod_stun)
      dodge = %Holder{spell: %Spell{id: 6}, auras: [%AuraData{type: :mod_dodge, amount: 100}]}
      entity = %{entity | unit: %{entity.unit | auras: [dodge | entity.unit.auras]}}
      spell = %{stun() | dmg_class: 2}

      {_entity, events} = SpellEffect.receive(entity, 2, spell, 100)
      assert [%Effects.SpellLogMiss{reason: :immune}] = events
    end
  end

  describe "blocked?/3" do
    test "positive immunity allows friendly effects unless explicitly forbidden", %{entity: entity} do
      entity = protect(entity, :effect_immunity, :heal)
      effect = %Effect{type: :heal, implicit_target_a: :target_ally}
      spell = %Spell{id: 3, effects: [effect]}
      refute EffectImmunity.blocked?(entity, spell, effect)

      [holder] = entity.unit.auras
      holder = %{holder | spell: %{holder.spell | attributes: MapSet.new([:immunity_to_hostile_and_friendly_effects])}}
      entity = %{entity | unit: %{entity.unit | auras: [holder]}}
      assert EffectImmunity.blocked?(entity, spell, effect)
    end

    test "negative immunity blocks positive effects but allows negative effects", %{entity: entity} do
      entity = protect(entity, :effect_immunity, :apply_aura)
      [holder] = entity.unit.auras
      entity = %{entity | unit: %{entity.unit | auras: [%{holder | negative?: true}]}}
      refute EffectImmunity.blocked?(entity, stun(), hd(stun().effects))
      effect = %Effect{type: :apply_aura, aura: :mod_stat, implicit_target_a: :target_ally}
      assert EffectImmunity.blocked?(entity, %Spell{id: 3, effects: [effect]}, effect)
    end
  end

  describe "apply_spell/5" do
    test "dispel immunity purges matching concealment and blocks its return until expiry", %{entity: entity} do
      stealth = concealment(5, :mod_stealth)
      invisibility = concealment(6, :mod_invisibility)
      {entity, _events} = Aura.apply_spell(entity, 1, 10, stealth, 0)
      {entity, _events} = Aura.apply_spell(entity, 1, 10, invisibility, 0)
      immunity = protection(:dispel_immunity, 5, [:immunity_purges_effect])
      {entity, _events} = Aura.apply_spell(entity, 2, 10, immunity, 100)

      refute Aura.has_spell?(entity, stealth.id)
      refute Aura.has_aura?(entity, :mod_stealth)
      assert Aura.has_spell?(entity, invisibility.id)

      {entity, _events} = Aura.apply_spell(entity, 1, 10, stealth, 200)
      refute Aura.has_spell?(entity, stealth.id)

      {entity, _events} = Aura.tick(entity, 1_100)
      {entity, _events} = Aura.apply_spell(entity, 1, 10, stealth, 1_101)
      assert Aura.has_spell?(entity, stealth.id)
    end

    test "one immunity spell can purge both stealth and invisibility", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 1, 10, concealment(5, :mod_stealth), 0)
      {entity, _events} = Aura.apply_spell(entity, 1, 10, concealment(6, :mod_invisibility), 0)
      immunity = protection(:dispel_immunity, 5, [:immunity_purges_effect])
      invisibility_immunity = %{hd(immunity.effects) | index: 1, misc_value: 6}
      immunity = %{immunity | effects: immunity.effects ++ [invisibility_immunity]}
      {entity, _events} = Aura.apply_spell(entity, 2, 10, immunity, 100)

      refute Aura.has_aura?(entity, :mod_stealth)
      refute Aura.has_aura?(entity, :mod_invisibility)
      assert Enum.map(entity.unit.auras, & &1.spell.id) == [immunity.id]
    end

    test "dispel immunity without the purge attribute retains existing concealment", %{entity: entity} do
      stealth = concealment(5, :mod_stealth)
      {entity, _events} = Aura.apply_spell(entity, 1, 10, stealth, 0)
      {entity, _events} = Aura.apply_spell(entity, 2, 10, protection(:dispel_immunity, 5), 100)
      before = Enum.find(entity.unit.auras, &(&1.spell.id == stealth.id))
      {entity, _events} = Aura.apply_spell(entity, 1, 10, stealth, 200)

      assert Enum.find(entity.unit.auras, &(&1.spell.id == stealth.id)) == before
    end

    test "dispel type zero never purges spells without a dispel type", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 1, 10, stun(), 0)
      immunity = protection(:dispel_immunity, 0, [:immunity_purges_effect])
      {entity, _events} = Aura.apply_spell(entity, 2, 10, immunity, 100)

      assert Aura.has_aura?(entity, :mod_stun)
    end

    test "purging removes the whole matching holder and clears control", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 10, stun(), 0)
      assert Aura.has_aura?(entity, :mod_stun)
      spell = protection(:state_immunity, :mod_stun, [:immunity_purges_effect])
      {entity, _events} = Aura.apply_spell(entity, 1, 10, spell, 100)
      refute Aura.has_aura?(entity, :mod_stun)
      assert Bitwise.band(entity.unit.flags || 0, 0x40000) == 0
      assert Aura.has_spell?(entity, spell.id)
    end

    test "nonpurging immunity preserves existing control but blocks refresh", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 10, stun(), 0)
      entity = protect(entity, :state_immunity, :mod_stun)
      before = Enum.find(entity.unit.auras, &(&1.spell.id == 2))
      {entity, _events} = Aura.apply_spell(entity, 2, 10, stun(), 500)
      assert Enum.find(entity.unit.auras, &(&1.spell.id == 2)) == before
    end

    test "overlapping sources retain protection until the last source is removed", %{entity: entity} do
      entity = protect(entity, :state_immunity, :mod_stun)
      second = %{protection(:state_immunity, :mod_stun) | id: 4}
      {entity, _events} = Aura.apply_spell(entity, 3, 10, second, 0)
      {entity, _events} = Aura.remove_spells(entity, [1], 100)
      assert EffectImmunity.blocked?(entity, stun(), hd(stun().effects))
      {entity, _events} = Aura.remove_spells(entity, [4], 200)
      {entity, _events} = SpellEffect.receive(entity, 2, stun(), 300)
      assert Aura.has_aura?(entity, :mod_stun)
    end

    test "expired protection permits control again", %{entity: entity} do
      entity = protect(entity, :state_immunity, :mod_stun)
      {entity, _events} = Aura.tick(entity, 1_001)
      {entity, _events} = SpellEffect.receive(entity, 2, stun(), 1_002)
      assert Aura.has_aura?(entity, :mod_stun)
    end

    test "death clears temporary immunity", %{entity: entity} do
      entity = protect(entity, :state_immunity, :mod_stun)
      entity = Core.take_damage(entity, 100, 100)
      assert entity.unit.health == 0
      refute Aura.has_spell?(entity, 1)
      refute EffectImmunity.blocked?(entity, stun(), hd(stun().effects))
    end

    test "purge preserves unrelated holders", %{entity: entity} do
      holder = %Holder{spell: %Spell{id: 5}, auras: [%AuraData{type: :mod_stat, amount: 2, misc_value: 0}]}
      entity = %{entity | unit: %{entity.unit | auras: [holder]}}
      spell = protection(:state_immunity, :mod_stun, [:immunity_purges_effect])
      {entity, _events} = Aura.apply_spell(entity, 1, 10, spell, 100)
      assert Aura.has_spell?(entity, 5)
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 10, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp protect(entity, type, value) do
    {entity, _events} = Aura.apply_spell(entity, 1, 10, protection(type, value), 0)
    entity
  end

  defp protection(type, value, attributes \\ []) do
    %Spell{
      id: 1,
      duration_ms: 1_000,
      attributes: MapSet.new(attributes),
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, misc_value: value, implicit_target_a: :caster}]
    }
  end

  defp stun do
    %Spell{
      id: 2,
      duration_ms: 5_000,
      school: :physical,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun, implicit_target_a: :target_enemy}]
    }
  end

  defp concealment(dispel_type, aura_type) do
    %Spell{
      id: 10 + dispel_type,
      dispel_type: dispel_type,
      duration_ms: 5_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: aura_type, base_points: 10, implicit_target_a: :caster}]
    }
  end
end
