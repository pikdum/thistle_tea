defmodule ThistleTea.Game.Entity.Logic.PowerBurnTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:mana_user]

  describe "receive/4" do
    test "caps damage at actual power lost", %{entity: entity, context: context} do
      {entity, [event]} = SpellEffect.receive(entity, context, burn_spell(:power_burn), 100)
      assert entity.unit.power1 == 0
      assert entity.unit.health == 925
      assert %Effects.SpellDamage{damage: 75, absorbed: 0} = event
      assert entity.internal.broadcast_update?
    end

    test "burns active energy without touching hidden mana", %{entity: entity, context: context} do
      entity = %{entity | unit: %{entity.unit | power_type: 3, power4: 60}}
      spell = burn_spell(:power_burn, misc_value: 3)
      {entity, [event]} = SpellEffect.receive(entity, context, spell, 100)
      assert entity.unit.power1 == 150
      assert entity.unit.power4 == 0
      assert entity.unit.health == 970
      assert event.damage == 30
    end

    test "ignores mismatched, invalid, empty, and dead resources", %{entity: entity, context: context} do
      for target <- [entity, %{entity | unit: %{entity.unit | power1: 0}}, %{entity | unit: %{entity.unit | health: 0}}],
          power <- [1, -1, 5] do
        {result, events} = SpellEffect.receive(target, context, burn_spell(:power_burn, misc_value: power), 100)
        assert result.unit.power1 == target.unit.power1
        assert result.unit.health == target.unit.health
        assert events == []
      end
    end

    test "zero conversion drains without damage", %{entity: entity, context: context} do
      {entity, [%Effects.SpellDamage{damage: 0}]} =
        SpellEffect.receive(entity, context, burn_spell(:power_burn, multiple_value: 0.0), 100)

      assert entity.unit.power1 == 0
      assert entity.unit.health == 1_000
    end

    test "shields absorb damage without restoring burned mana", %{entity: entity, context: context} do
      for {capacity, health} <- [{30, 955}, {100, 1_000}] do
        target = with_aura(entity, :school_absorb, capacity, 32)
        {target, [event]} = SpellEffect.receive(target, context, burn_spell(:power_burn), 100)
        assert target.unit.power1 == 0
        assert target.unit.health == health
        assert event.absorbed == min(capacity, 75)
      end
    end

    test "honors conversion modifiers and criticals without adding spell power", %{entity: entity, context: context} do
      context = %{
        context
        | spell_crit_chance: 100,
          spell_damage_bonus: %{shadow: 1_000},
          spell_modifiers: [%AuraData{type: :add_pct_modifier, misc_value: 27, amount: 100}]
      }

      {entity, [event]} = SpellEffect.receive(entity, context, burn_spell(:power_burn), 100)
      assert entity.unit.power1 == 0
      assert entity.unit.health == 775
      assert event.damage == 225
      assert event.crit?
    end

    test "damage immunity preserves both health and mana", %{entity: entity, context: context} do
      entity = with_aura(entity, :school_immunity, 0, 32)

      {entity, [%Effects.SpellLogMiss{reason: :immune}]} =
        SpellEffect.receive(entity, context, burn_spell(:power_burn), 100)

      assert entity.unit.power1 == 150
      assert entity.unit.health == 1_000
    end
  end

  describe "tick/2" do
    test "absorbs periodic damage while consuming mana", %{entity: entity, context: context} do
      entity = with_aura(entity, :school_absorb, 100, 32)
      {entity, _} = Aura.apply_spell(entity, context, burn_spell(:apply_aura), 100)
      {entity, [event]} = Aura.tick(entity, 1_100)
      assert {entity.unit.power1, entity.unit.health} == {0, 1_000}
      assert event.absorbed == 75
      assert event.periodic?
    end

    test "lethal burns do not restore their holder after death", %{entity: entity, context: context} do
      entity = %{entity | unit: %{entity.unit | health: 50}}
      {entity, _} = Aura.apply_spell(entity, context, burn_spell(:apply_aura), 100)
      {entity, [event]} = Aura.tick(entity, 1_100)
      assert event.damage == 75
      assert entity.unit.health == 0
      assert entity.unit.auras == []
      assert Aura.next_event_at(entity) == nil
    end

    test "non-mana forms preserve hidden mana and resume after changing back", %{entity: entity, context: context} do
      entity = %{entity | unit: %{entity.unit | power_type: 3, power4: 100}}
      {entity, _} = Aura.apply_spell(entity, context, burn_spell(:apply_aura), 100)
      {entity, []} = Aura.tick(entity, 1_100)
      assert {entity.unit.power1, entity.unit.power4, entity.unit.health} == {150, 100, 1_000}
      entity = %{entity | unit: %{entity.unit | power_type: 0}}
      {entity, [_event]} = Aura.tick(entity, 2_100)
      assert entity.unit.power1 == 0
      assert entity.unit.health == 925
    end

    test "schedules burns, uses remaining mana, and stops damage when empty", %{entity: entity, context: context} do
      {entity, _} = Aura.apply_spell(entity, context, burn_spell(:apply_aura, base_points: 99), 100)
      assert Aura.next_event_at(entity) == 1_100
      {entity, []} = Aura.tick(entity, 1_099)
      assert entity.unit.power1 == 150
      {entity, [first]} = Aura.tick(entity, 1_100)
      assert {entity.unit.power1, entity.unit.health} == {50, 950}
      assert %Effects.SpellDamage{damage: 50, periodic?: true, proc_type: :deal_harmful_periodic} = first
      {entity, [second]} = Aura.tick(entity, 2_100)
      assert {entity.unit.power1, entity.unit.health} == {0, 925}
      assert second.damage == 25
      {entity, []} = Aura.tick(entity, 3_100)
      assert entity.unit.health == 925
      assert entity.unit.auras == []
      assert Aura.next_event_at(entity) == nil
    end

    test "periodic burns can critically hit using the caster snapshot", %{entity: entity, context: context} do
      context = %{context | spell_crit_chance: 100}
      {entity, _} = Aura.apply_spell(entity, context, burn_spell(:apply_aura), 100)
      {entity, [event]} = Aura.tick(entity, 1_100)
      assert entity.unit.health == 888
      assert event.crit?
      assert event.periodic?
    end

    test "zero-conversion periodic burns still consume mana", %{entity: entity, context: context} do
      {entity, _} = Aura.apply_spell(entity, context, burn_spell(:apply_aura, multiple_value: 0.0), 100)
      {entity, [%Effects.SpellDamage{damage: 0}]} = Aura.tick(entity, 1_100)
      assert entity.unit.power1 == 0
      assert entity.unit.health == 1_000
      assert Aura.next_event_at(entity) == 2_100
    end

    test "immunity blocks a tick and advances its deadline", %{entity: entity, context: context} do
      {entity, _} = Aura.apply_spell(entity, context, burn_spell(:apply_aura), 100)
      entity = with_aura(entity, :damage_immunity, 0, 32)
      {entity, [%Effects.SpellDamageImmune{}]} = Aura.tick(entity, 1_100)
      assert {entity.unit.power1, entity.unit.health} == {150, 1_000}
      assert Aura.next_event_at(entity) == 2_100
    end

    test "refresh preserves the pending tick and removal clears it", %{entity: entity, context: context} do
      spell = burn_spell(:apply_aura)
      {entity, _} = Aura.apply_spell(entity, context, spell, 100)
      {entity, _} = Aura.apply_spell(entity, context, spell, 500)
      assert length(entity.unit.auras) == 1
      assert Aura.next_event_at(entity) == 1_100
      assert hd(entity.unit.auras).expires_at == 3_500
      {entity, []} = Aura.tick(entity, 1_099)
      assert entity.unit.power1 == 150
      {entity, _} = Aura.remove_spells(entity, [spell.id], 1_099)
      {entity, []} = Aura.tick(entity, 1_500)
      assert entity.unit.power1 == 150
      assert Aura.next_event_at(entity) == nil
    end

    test "death clears the burn and its pending deadline", %{entity: entity, context: context} do
      {entity, _} = Aura.apply_spell(entity, context, burn_spell(:apply_aura), 100)
      entity = Core.take_damage(entity, 1_000, 500, environmental?: true)
      assert entity.unit.auras == []
      {entity, []} = Aura.tick(entity, 1_100)
      assert entity.unit.power1 == 150
      assert Aura.next_event_at(entity) == nil
    end
  end

  defp mana_user(_context) do
    entity = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, power_type: 0, power1: 150, max_power1: 150, auras: []},
      internal: %Internal{world: WorldRef.open(0)}
    }

    %{entity: entity, context: %CastContext{caster_guid: 2, caster_level: 60}}
  end

  defp burn_spell(type, opts \\ []) do
    effect =
      struct!(
        %Effect{
          index: 0,
          type: type,
          aura: if(type == :apply_aura, do: :periodic_power_burn),
          base_points: 199,
          base_dice: 1,
          die_sides: 1,
          misc_value: 0,
          multiple_value: 0.5,
          amplitude_ms: 1_000,
          implicit_target_a: :target_enemy
        },
        opts
      )

    %Spell{id: 19_659, school: :shadow, dmg_class: 1, duration_ms: 3_000, effects: [effect]}
  end

  defp with_aura(entity, type, amount, mask) do
    holder = %Holder{
      spell: %Spell{id: 17},
      caster_guid: 1,
      auras: [%AuraData{type: type, amount: amount, misc_value: mask}]
    }

    %{entity | unit: %{entity.unit | auras: [holder | entity.unit.auras]}}
  end
end
