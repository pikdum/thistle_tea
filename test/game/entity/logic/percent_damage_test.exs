defmodule ThistleTea.Game.Entity.Logic.PercentDamageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Dispel
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "apply_spell/4" do
    test "schedules harmful ticks without caster damage bonuses", %{entity: entity} do
      spell = damage()

      context = %CastContext{
        caster_guid: 2,
        caster_level: 60,
        spell_damage_bonus: %{physical: 1_000},
        spell_damage_versus: [{1, 1_000}],
        effect_damage_multiplier: 3.0,
        damage_done_multiplier: 2.0
      }

      {entity, _events} = Aura.apply_spell(entity, context, spell, 100)
      assert Aura.next_event_at(entity) == 1_100
      assert [holder] = entity.unit.auras
      assert holder.negative?
      assert hd(holder.auras).amount == 10
      {entity, events} = Aura.tick(entity, 1_100)
      assert entity.unit.health == 900
      assert [%Effects.SpellDamage{damage: 100, periodic?: true, source_guid: 2, target_guid: 1}] = events
    end

    test "keeps independent caster holders and stacks within each source", %{entity: entity} do
      spell = %{damage() | stack_amount: 3}
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 100)
      {entity, _events} = Aura.apply_spell(entity, 3, 60, spell, 0)
      assert length(entity.unit.auras) == 2
      {entity, events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 700
      assert Enum.sort(Enum.map(events, & &1.damage)) == [100, 200]
    end

    test "state immunity blocks the harmful aura even with a friendly target", %{entity: entity} do
      immunity = protection(:state_immunity, :periodic_damage_percent)
      {entity, _events} = Aura.apply_spell(entity, 1, 60, immunity, 0)
      effect = %{hd(damage().effects) | implicit_target_a: :caster}
      {entity, _events} = Aura.apply_spell(entity, 1, 60, %{damage() | effects: [effect]}, 0)
      refute Aura.has_spell?(entity, 1)
    end
  end

  describe "tick/2" do
    test "uses current maximum health for players and creatures", %{entity: entity} do
      player = %Character{object: entity.object, player: %Player{}, unit: entity.unit, internal: entity.internal}

      for entity <- [entity, player] do
        {entity, _events} = Aura.apply_spell(entity, 2, 60, damage(), 0)
        {entity, []} = Aura.tick(entity, 999)
        assert entity.unit.health == 1_000
        {entity, _events} = Aura.tick(entity, 1_000)
        assert entity.unit.health == 900
        entity = %{entity | unit: %{entity.unit | max_health: 2_007}}
        {entity, events} = Aura.tick(entity, 2_000)
        assert entity.unit.health == 700
        assert [%Effects.SpellDamage{damage: 200}] = events
        assert entity.internal.broadcast_update?
      end
    end

    test "nonpositive percentages cannot heal", %{entity: entity} do
      for amount <- [0, -10] do
        {entity, _events} = Aura.apply_spell(entity, 2, 60, damage(base_points: amount), 0)
        {entity, events} = Aura.tick(entity, 1_000)
        assert entity.unit.health == 1_000
        assert [%Effects.SpellDamage{damage: 0}] = events
      end
    end

    test "damage immunity preserves cadence and damage resumes after removal", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 60, damage(), 0)
      {entity, _events} = Aura.apply_spell(entity, 1, 60, protection(:damage_immunity, 1), 0)
      {entity, events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 1_000
      assert [%Effects.SpellDamageImmune{spell_id: 1}] = events
      {entity, _events} = Aura.remove_spells(entity, [2], 1_500)
      assert Aura.next_event_at(entity) == 2_000
      {entity, events} = Aura.tick(entity, 2_000)
      assert entity.unit.health == 900
      assert [%Effects.SpellDamage{damage: 100}] = events
    end

    test "absorption consumes shields through the shared transition", %{entity: entity} do
      shield = protection(:school_absorb, 1, 150)

      for spell <- [damage(), damage(aura: :periodic_damage, base_points: 100)],
          order <- [[spell, shield], [shield, spell]] do
        entity =
          Enum.reduce(order, entity, fn spell, entity ->
            {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
            entity
          end)

        {entity, events} = Aura.tick(entity, 1_000)
        assert entity.unit.health == 1_000
        assert [%Effects.SpellDamage{damage: 100, absorbed: 100}] = events
        assert Aura.has_spell?(entity, 2)
        {entity, events} = Aura.tick(entity, 2_000)
        assert entity.unit.health == 950
        assert [%Effects.SpellDamage{damage: 100, absorbed: 50}] = events
        refute Aura.has_spell?(entity, 2)
      end
    end

    test "school resistance reduces damage before absorption", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | base_fire_resistance: 300}}
      spell = %{damage() | school: :fire}
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      :rand.seed(:exsss, {1, 1, 1})
      {entity, events} = Aura.tick(entity, 1_000)
      assert [%Effects.SpellDamage{damage: dealt, resisted: resisted}] = events
      assert resisted > 0
      assert dealt + resisted == 100
      assert entity.unit.health == 1_000 - dealt
    end

    test "combat feedback matches damage after received modifiers and absorption", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 60, damage(), 0)
      {entity, _events} = Aura.apply_spell(entity, 1, 60, protection(:mod_damage_percent_taken, 1, -50), 0)
      shield = %{protection(:school_absorb, 1, 30) | id: 3}
      {entity, _events} = Aura.apply_spell(entity, 1, 60, shield, 0)
      {entity, events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 980
      assert [%Effects.SpellDamage{damage: 50, absorbed: 30}] = events
    end

    test "delayed ticks advance once and final ticks expire", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 60, damage(), 0)
      {entity, events} = Aura.tick(entity, 3_500)
      assert entity.unit.health == 900
      assert length(events) == 1
      assert Aura.next_event_at(entity) == 4_000
      {entity, _events} = Aura.tick(entity, 5_000)
      assert entity.unit.health == 800
      assert entity.unit.auras == []
      assert Aura.next_event_at(entity) == nil
    end

    test "lethal ticks clear auras and cannot be undone by later healing", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | health: 50}}
      heal = %Effect{index: 1, type: :apply_aura, aura: :periodic_heal, base_points: 200, amplitude_ms: 1_000}
      spell = %{damage() | effects: damage().effects ++ [heal]}
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {entity, events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 0
      assert entity.unit.auras == []
      assert Aura.next_event_at(entity) == nil
      assert [%Effects.SpellDamage{damage: 100}] = events
    end
  end

  describe "aura lifecycle" do
    test "dispel and death stop scheduled ticks", %{entity: entity} do
      spell = %{damage() | dispel_type: 1}
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {dispelled, _events, [1]} = Dispel.apply(entity, 1, 500, :negative, 1)
      dead = Core.take_damage(entity, 1_000, 500)

      for entity <- [dispelled, dead] do
        {entity, events} = Aura.tick(entity, 1_000)
        assert entity.unit.auras == []
        assert Aura.next_event_at(entity) == nil
        assert events == []
      end
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, auras: []},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp damage(opts \\ []) do
    effect = %Effect{
      index: 0,
      type: :apply_aura,
      aura: :periodic_damage_percent,
      base_points: 10,
      amplitude_ms: 1_000,
      implicit_target_a: :target_enemy
    }

    %Spell{id: 1, school: :physical, duration_ms: 5_000, effects: [struct!(effect, opts)]}
  end

  defp protection(type, mask, amount \\ 0) do
    %Spell{
      id: 2,
      duration_ms: 5_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, misc_value: mask, base_points: amount}]
    }
  end
end
