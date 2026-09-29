defmodule ThistleTea.Game.Core.Spell.OwnedGameObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Spell.SpellTargetResolver

  setup [:caster]

  describe "receive/4" do
    test "creates each slot on the caster with an explicit zero destination", %{caster: caster, context: context} do
      effects = for slot <- 1..4, do: effect(slot)
      spell = %Spell{id: 1499, duration_ms: 60_000, effects: effects}
      context = %{context | destination_position: {0.0, 0.0, 0.0}}

      assert SpellTargetResolver.resolve(caster, spell, Target.unit(2)) == [1]
      {_, events} = SpellEffect.receive(caster, context, spell, 1_000)
      assert Enum.map(events, & &1.slot) == [1, 2, 3, 4]

      for event <- events do
        assert %Effects.SummonGameObject{owned?: true, spell_id: 1499, duration_ms: 60_000} = event
        assert event.position == {0.0, 0.0, 0.0, 0.0}
      end

      other = %{caster | object: %Object{guid: 2}}
      assert {_, []} = SpellEffect.receive(other, %{context | target_role: :other}, spell, 1_000)
    end

    test "untimed summons use the owner's position and default to the first slot", %{caster: caster, context: context} do
      spell = %Spell{id: 1499, duration_ms: -1, effects: [%{effect(1) | summon_slot: nil}]}
      {_, [event]} = SpellEffect.receive(caster, context, spell, 1_000)
      assert event.slot == 1
      assert event.duration_ms == 0
      assert event.position == nil
    end
  end

  defp caster(_context) do
    world = WorldRef.open(999)

    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100},
      internal: %Internal{world: world}
    }

    %{
      caster: caster,
      context: %CastContext{caster_guid: 1, caster_level: 10, caster_position: {world, 10.0, 20.0, 30.0}}
    }
  end

  defp effect(slot),
    do: %Effect{
      index: slot - 1,
      type: :summon_game_object,
      summon_slot: slot,
      misc_value: 2561,
      implicit_target_a: :minion_position
    }
end
