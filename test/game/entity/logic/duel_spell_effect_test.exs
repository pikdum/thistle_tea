defmodule ThistleTea.Game.Entity.Logic.DuelSpellEffectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  describe "receive/4 duel effect" do
    test "enqueues a duel request with a midpoint flag position" do
      world = WorldRef.open(0)

      target = %Character{
        object: %Object{guid: 2},
        unit: %Unit{health: 100, auras: []},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {10.0, 8.0, 4.0, 1.0}}
      }

      spell = %Spell{
        id: 7_266,
        effects: [%Effect{index: 0, type: :duel, misc_value: 21_680, implicit_target_a: :any_unit}]
      }

      context = %CastContext{
        caster_guid: 1,
        caster_level: 20,
        caster_type: :player,
        caster_position: {world, 2.0, 4.0, 3.0},
        caster_orientation: 0.5,
        target_guid: 2,
        target_role: :other,
        spell: spell
      }

      assert {^target, [event]} = SpellEffect.receive(target, context, spell, 1_000)
      assert is_struct(event, Effects.DuelRequest)
      assert event.source_guid == 1
      assert event.target_guid == 2
      assert event.entry == 21_680
      assert event.position == {world, 6.0, 6.0, 3.0}
      assert event.facing == 0.5
    end
  end
end
