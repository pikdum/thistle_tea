defmodule ThistleTea.Game.Entity.Logic.Aura.DispelTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura.Dispel
  alias ThistleTea.Game.Entity.Logic.Aura.Periodic
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "apply/5" do
    test "removes one stack and recomputes stats without refreshing the aura", %{entity: entity} do
      {updated, _events, [10]} = Dispel.apply(entity, 1, 2_000, :negative, 1)
      assert [%Holder{stacks: 2, slot: 32, expires_at: 10_000, auras: [aura]}] = updated.unit.auras
      assert aura.next_tick_at == 3_000
      assert updated.unit.strength == 80
      assert :binary.at(updated.unit.aura_applications, 32) == 1
      assert updated.internal.broadcast_update?
    end

    test "multiple attempts can remove stacks from the same holder", %{entity: entity} do
      {updated, _events, [10]} = Dispel.apply(entity, 1, 2_000, :negative, 2)
      assert [%Holder{stacks: 1}] = updated.unit.auras
      assert updated.unit.strength == 90

      {updated, _events, [10]} = Dispel.apply(updated, 1, 3_000, :negative, 4)
      assert updated.unit.auras == []
      assert updated.unit.strength == 100
      assert updated.unit.aura == 0
    end

    test "keeps independent casters and nonmatching holders", %{entity: entity} do
      [holder] = entity.unit.auras
      other = %{holder | caster_guid: 3, stacks: 1}
      poison = %{holder | spell: %{holder.spell | id: 11, dispel_type: 4}}
      entity = %{entity | unit: %{entity.unit | auras: [holder, other, poison]}}
      {updated, _events, [10, 10]} = Dispel.apply(entity, 1, 2_000, :negative, 10)
      assert updated.unit.auras == [poison]
    end

    test "does not change an ineligible target", %{entity: entity} do
      assert {^entity, [], []} = Dispel.apply(entity, 4, 2_000, :negative, 1)
      assert {^entity, [], []} = Dispel.apply(entity, 1, 2_000, :positive, 1)
      assert {^entity, [], []} = Dispel.apply(entity, 1, 2_000, :negative, 0)
    end
  end

  describe "matches?/4" do
    test "all-dispel includes the four standard categories" do
      for all <- [7, -1], type <- [1, 2, 3, 4] do
        assert Dispel.matches?(type, :negative, all, :negative)
      end

      for type <- [0, 5, 6, 7, 9] do
        refute Dispel.matches?(type, :negative, 7, :negative)
      end
    end

    test "magic and poison respect polarity while other categories do not" do
      for type <- [1, 4] do
        assert Dispel.matches?(type, :negative, type, :negative)
        refute Dispel.matches?(type, :positive, type, :negative)
        refute Dispel.matches?(type, :negative, type, :positive)
      end

      for type <- [2, 3, 9] do
        assert Dispel.matches?(type, :positive, type, :negative)
      end
    end
  end

  describe "tick/2" do
    test "stacked poison damage decreases after a partial cure and stops on expiry", %{entity: entity} do
      [holder] = entity.unit.auras
      aura = %AuraData{type: :periodic_damage, amount: 10, amplitude_ms: 3_000, next_tick_at: 3_000}
      holder = %{holder | spell: %{holder.spell | dispel_type: 4}, auras: [aura]}
      entity = %{entity | unit: %{entity.unit | auras: [holder]}}

      {entity, events} = Periodic.tick(entity, 3_000)
      assert entity.unit.health == 70
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 30}, &1))

      {entity, _events, [10]} = Dispel.apply(entity, 4, 4_000, :negative, 1)
      {entity, events} = Periodic.tick(entity, 6_000)
      assert entity.unit.health == 50
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 20}, &1))

      {entity, _events, [10]} = Dispel.apply(entity, 4, 7_000, :negative, 1)
      {entity, events} = Periodic.tick(entity, 9_000)
      assert entity.unit.health == 40
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 10}, &1))

      {entity, _events} = Periodic.tick(entity, 10_000)
      assert entity.unit.auras == []
      assert {^entity, []} = Periodic.tick(entity, 12_000)
    end

    test "Ignite's accumulated damage is not multiplied again", %{entity: entity} do
      [holder] = entity.unit.auras
      aura = %AuraData{type: :periodic_damage, amount: 10, amplitude_ms: 2_000, next_tick_at: 2_000}
      holder = %{holder | spell: %{holder.spell | id: 12_654}, auras: [aura]}
      entity = %{entity | unit: %{entity.unit | auras: [holder]}}
      {entity, events} = Periodic.tick(entity, 2_000)
      assert entity.unit.health == 90
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 10}, &1))
    end
  end

  describe "receive/4" do
    test "logs a partial removal and triggers Devour Magic healing", %{entity: entity} do
      spell = %Spell{
        id: 19_505,
        script_name: "spell_warlock_devour_magic",
        effects: [%Effect{index: 0, type: :dispel, misc_value: 1}]
      }

      context = %CastContext{caster_guid: 2, caster_level: 40, target_hostile?: false}
      {updated, events} = SpellEffect.receive(entity, context, spell, 2_000)
      assert [%Holder{stacks: 2}] = updated.unit.auras
      assert %Effects.SpellDispel{source_guid: 2, target_guid: 1, spell_ids: [10]} in events
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{target_guid: 2, spell_id: 19_658}, &1))

      {^updated, events} = SpellEffect.receive(updated, %{context | target_hostile?: true}, spell, 3_000)
      refute Enum.any?(events, &match?(%Effects.SpellDispel{}, &1))
      refute Enum.any?(events, &match?(%Effects.TriggerSpell{}, &1))
    end
  end

  defp entity(_context) do
    holder = %Holder{
      spell: %Spell{id: 10, dispel_type: 1, stack_amount: 5},
      caster_guid: 2,
      stacks: 3,
      slot: 32,
      negative?: true,
      expires_at: 10_000,
      auras: [%AuraData{type: :mod_stat, misc_value: 0, amount: -10, next_tick_at: 3_000}]
    }

    entity = %Mob{
      object: %Object{guid: 1},
      unit: UnitSync.sync_unit(%Unit{level: 40, health: 100, max_health: 100, base_strength: 100, auras: [holder]}),
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{entity: entity}
  end
end
