defmodule ThistleTea.Game.Entity.Logic.EngineeringTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.RandomChoice
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  describe "receive/4" do
    test "the remote selects possession, rooting, or a target-owned enrage with equal weights" do
      entity = target()
      context = %CastContext{caster_guid: 1, caster_level: 60, target_guid: 2, cast_item_guid: 42}
      spell = device_spell(8344)
      assert {^entity, [%RandomChoice{} = choice]} = SpellEffect.receive(entity, context, spell, 0)
      assert RandomChoice.total_weight(choice) == 3

      for {roll, id, source, level} <- [{1, 8345, 1, 60}, {2, 8346, 1, 60}, {3, 8599, 2, 30}] do
        assert [
                 %Effects.TriggerSpell{
                   source_guid: ^source,
                   source_level: ^level,
                   target_guid: 2,
                   spell_id: ^id,
                   resolve_targets?: true,
                   cast_item_guid: nil
                 }
               ] = RandomChoice.select(choice, roll)
      end
    end

    test "the cap preserves failures and reversed control as distinct outcomes" do
      entity = target()
      context = %CastContext{caster_guid: 1, caster_level: 60, target_guid: 2, caster_shapeshift_form: 0}
      assert {^entity, [%RandomChoice{} = choice]} = SpellEffect.receive(entity, context, device_spell(13_180), 0)
      assert RandomChoice.total_weight(choice) == 6
      assert RandomChoice.select(choice, 1) == []

      assert [%Effects.TriggerSpell{source_guid: 2, source_level: 30, target_guid: 1, spell_id: 13_181}] =
               RandomChoice.select(choice, 2)

      for roll <- 3..6 do
        assert [%Effects.TriggerSpell{source_guid: 1, source_level: 60, target_guid: 2, spell_id: 13_181}] =
                 RandomChoice.select(choice, roll)
      end

      for form <- [1, 8, 17, 28] do
        {^entity, [%RandomChoice{} = shifted]} =
          SpellEffect.receive(entity, %{context | caster_shapeshift_form: form}, device_spell(13_180), 0)

        assert RandomChoice.total_weight(shifted) == 6
        assert RandomChoice.select(shifted, 2) == []
        assert RandomChoice.select(shifted, 3) == RandomChoice.select(choice, 3)
      end
    end

    test "control device effects execute only once and ignore dead recipients" do
      entity = target()
      context = %CastContext{caster_guid: 1, caster_level: 60, target_guid: 2}

      for id <- [8344, 13_180] do
        spell = device_spell(id)
        second = %{spell | effects: [%{hd(spell.effects) | index: 1}]}
        assert {^entity, []} = SpellEffect.receive(entity, context, second, 0)
        dead = %{entity | unit: %{entity.unit | health: 0}}
        assert {^dead, []} = SpellEffect.receive(dead, context, spell, 0)
      end
    end

    test "the dispenser selects a summon or malfunction only for an item cast" do
      entity = target()
      context = %CastContext{caster_guid: 2, caster_level: 60, target_guid: 2, cast_item_guid: 42}
      spell = %Spell{id: 23_134, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :caster}]}
      assert {^entity, [%RandomChoice{} = choice]} = SpellEffect.receive(entity, context, spell, 0)

      assert [%Effects.TriggerSpell{spell_id: 13_261, cast_item_guid: nil, resolve_targets?: true}] =
               RandomChoice.select(choice, 1)

      for roll <- 2..10 do
        assert [%Effects.TriggerSpell{spell_id: 13_258, cast_item_guid: 42, source_guid: 2, target_guid: 2}] =
                 RandomChoice.select(choice, roll)
      end

      assert {^entity, []} = SpellEffect.receive(entity, %{context | cast_item_guid: nil}, spell, 0)
      assert {^entity, []} = SpellEffect.receive(entity, %{context | caster_guid: 1}, spell, 0)
    end

    test "a net requests one caster-owned outcome from its first dummy effect" do
      entity = target()
      context = %CastContext{caster_guid: 1, caster_level: 60, target_guid: 2, cast_item_guid: 42}
      spell = %Spell{id: 13_120, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :target_enemy}]}
      assert {^entity, [%RandomChoice{} = choice]} = SpellEffect.receive(entity, context, spell, 0)

      for {roll, id} <- [{1, 16_566}, {2, 13_119}, {3, 13_099}, {10, 13_099}] do
        assert [%Effects.TriggerSpell{source_guid: 1, target_guid: 2, spell_id: ^id, cast_item_guid: nil} = trigger] =
                 RandomChoice.select(choice, roll)

        assert [%Effects.TriggerSpellRequest{source_guid: 1, target_guid: 2, spell_id: ^id}] =
                 Spells.resolve(entity, trigger)
      end

      second = %{spell | effects: [%{hd(spell.effects) | index: 1}]}
      assert {^entity, []} = SpellEffect.receive(entity, context, second, 0)
    end
  end

  describe "apply_spell/4" do
    test "the backfire marker never occupies an aura slot or survives to restoration" do
      entity = target()
      context = %CastContext{caster_guid: 1, caster_level: 60}
      spell = %Spell{id: 13_139, duration_ms: -1, effects: [%Effect{type: :apply_aura, aura: :dummy}]}

      assert {^entity, [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, spell_id: 13_138, target_role: :other}]} =
               Aura.apply_spell(entity, context, spell, 0)
    end
  end

  defp target do
    %Mob{
      object: %Object{guid: 2},
      unit: %Unit{level: 30, health: 100, max_health: 100, auras: []},
      internal: %Internal{}
    }
  end

  defp device_spell(id),
    do: %Spell{id: id, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :target_enemy}]}
end
