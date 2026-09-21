defmodule ThistleTea.Game.Entity.Logic.WildObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "receive/4" do
    test "summons once on the caster even with another selected target", %{caster: caster, context: context} do
      spell = spell()
      assert SpellTargetResolver.resolve(caster, spell, Target.unit(2)) == [2, 1]
      {_, events} = SpellEffect.receive(caster, context, spell, 1_000)

      assert [
               %Effects.SummonGameObject{
                 entry: 161_513,
                 owned?: false,
                 duration_ms: 120_000,
                 position: {10.0, 20.0, 30.0, +0.0}
               }
             ] = events

      other = %{caster | object: %Object{guid: 2}}
      assert {_, []} = SpellEffect.receive(other, %{context | target_role: :other}, spell, 1_000)
    end

    test "keeps an explicit destination including zero coordinates", %{caster: caster, context: context} do
      context = %{context | destination_position: {0.0, 0.0, 0.0}}
      {_, [%Effects.SummonGameObject{position: position}]} = SpellEffect.receive(caster, context, spell(), 1_000)
      assert position == {0.0, 0.0, 0.0, 0.0}
    end

    test "retains separate objects from separate effects", %{caster: caster, context: context} do
      first = hd(spell().effects)
      second = %{first | index: 1, misc_value: 177_683}
      spell = %{spell() | effects: [first, second], duration_ms: -1}
      {_, events} = SpellEffect.receive(caster, context, spell, 1_000)
      assert Enum.map(events, & &1.entry) == [161_513, 177_683]
      assert Enum.all?(events, &(&1.duration_ms == 0))
    end

    test "uses the effect radius for forward placement", %{caster: caster, context: context} do
      effect = %{hd(spell().effects) | implicit_target_a: 47, radius_yards: 3.0}
      spell = %{spell() | effects: [effect]}
      {_, [event]} = SpellEffect.receive(caster, context, spell, 1_000)
      assert event.position == {13.0, 20.0, 30.0, 0.0}
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
      context: %CastContext{
        caster_guid: 1,
        caster_level: 10,
        caster_position: {world, 10.0, 20.0, 30.0},
        caster_orientation: 0.0
      }
    }
  end

  defp spell do
    %Spell{
      id: 13_563,
      duration_ms: 120_000,
      effects: [%Effect{index: 0, type: :summon_object_wild, misc_value: 161_513, implicit_target_a: :minion_position}]
    }
  end
end
