defmodule ThistleTea.Game.Core.Aura.SeparationAnxietyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:combatants]

  describe "tick/3" do
    test "hidden auras check every five seconds and the add casts its own buff", ctx do
      for {spell_id, buff_id} <- [{21_094, 21_095}, {23_487, 23_492}] do
        {add, context} = bind(ctx, spell_id)
        guid = add.object.guid
        [holder] = add.unit.auras
        assert holder.cast_context == context
        assert Aura.next_event_at(add) == 5_000
        assert {^add, []} = Aura.tick(add, 4_999, contexts(add, context))
        {add, events} = Aura.tick(add, 5_000, contexts(add, context))

        assert [%Effects.TriggerSpell{source_guid: ^guid, target_guid: ^guid, spell_id: ^buff_id} = cast] =
                 Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))

        assert cast.triggering_spell_id == spell_id
        assert Aura.next_event_at(add) == 10_000
      end
    end

    test "uses both bounding radii with a strict three-dimensional boundary", ctx do
      {add, context} = bind(ctx, 23_487)

      for {position, separated?} <- [
            {{103.499, 0.0, 0.0, 0.0}, false},
            {{103.5, 0.0, 0.0, 0.0}, true},
            {{0.0, 0.0, 103.5, 0.0}, true},
            {{90.0, 0.0, 40.0, 0.0}, false}
          ] do
        positioned = %{add | movement_block: %{add.movement_block | position: position}}
        {_add, events} = Aura.tick(positioned, 5_000, contexts(positioned, context))
        assert Enum.any?(events, &is_struct(&1, Effects.TriggerSpell)) == separated?
      end
    end

    test "returning to the boss stops refreshes and lets the buff expire", ctx do
      {add, context} = bind(ctx, 21_094)

      buff = %Spell{
        id: 21_095,
        duration_ms: 5_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_damage_percent_done, base_points: 200}]
      }

      {add, _events} = Aura.apply_spell(add, add.object.guid, 60, buff, 5_000)
      closer = %{context | caster_position: {add.internal.world, 10.0, 0.0, 0.0}}
      {add, events} = Aura.tick(add, 9_999, contexts(add, closer))
      assert Aura.has_spell?(add, 21_095)
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
      {add, events} = Aura.tick(add, 10_000, contexts(add, closer))
      refute Aura.has_spell?(add, 21_095)
      assert Aura.has_spell?(add, 21_094)
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
    end

    test "dead, missing and other-copy sources never empower the add", ctx do
      {add, context} = bind(ctx, 23_487)

      for invalid <- [
            %{context | caster_available?: false},
            %{context | caster_position: nil},
            %{context | caster_position: {WorldRef.instance(409, Unique.integer()), 0.0, 0.0, 0.0}}
          ] do
        {ticked, events} = Aura.tick(add, 5_000, contexts(add, invalid))
        assert Aura.has_spell?(ticked, 23_487)
        assert Aura.next_event_at(ticked) == 10_000
        refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
      end

      dead = %{add | unit: %{add.unit | health: 0}}
      {_dead, events} = Aura.tick(dead, 5_000, contexts(dead, context))
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
    end

    test "reads the aura effect's radius and ignores unrelated dummy auras", ctx do
      {add, context} = bind(ctx, 23_487)
      [holder] = add.unit.auras
      spell = %{holder.spell | effects: [%{hd(holder.spell.effects) | radius_yards: 200.0}]}
      add = %{add | unit: %{add.unit | auras: [%{holder | spell: spell}]}}
      {_add, events} = Aura.tick(add, 5_000, contexts(add, context))
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))

      unrelated = %{spell | id: Unique.integer()}
      {add, _events} = Aura.apply_spell(ctx.add, context, unrelated, 0)
      assert Aura.next_event_at(add) == nil
    end
  end

  defp bind(ctx, spell_id) do
    spell = %Spell{
      id: spell_id,
      duration_ms: -1,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy, radius_yards: 100.0}]
    }

    context = %CastContext{
      spell: spell,
      caster_guid: ctx.boss,
      caster_level: 63,
      caster_position: {ctx.add.internal.world, 0.0, 0.0, 0.0},
      caster_bounding_radius: 2.0
    }

    {add, _events} = Aura.apply_spell(ctx.add, context, spell, 0)
    {add, context}
  end

  defp contexts(add, context) do
    for holder <- add.unit.auras, into: %{}, do: {{holder.spell.id, holder.caster_guid, holder.item_source}, context}
  end

  defp combatants(_context) do
    %{
      boss: Unique.integer(),
      add: %Mob{
        object: %Object{guid: Unique.integer()},
        unit: %Unit{health: 100, max_health: 100, level: 60, bounding_radius: 1.5, auras: []},
        internal: %Internal{world: WorldRef.instance(409, Unique.integer())},
        movement_block: %MovementBlock{position: {110.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
