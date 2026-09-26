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
    %Mob{object: %Object{guid: 2}, unit: %Unit{health: 100, max_health: 100, auras: []}, internal: %Internal{}}
  end
end
