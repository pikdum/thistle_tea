defmodule ThistleTea.Game.World.Loader.CapturedFollowerDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Test.Unique

  @moduletag :dbc_db

  describe "load/1" do
    test "real muzzle and collar pulses trigger capture and indefinite dummy auras acquire lifetime checks" do
      for {capture, trigger, tracking, entry} <- [{21_794, 21_795, 21_827, 10_981}, {21_866, 21_867, 21_863, 10_990}] do
        spell = SpellLoader.load(capture)
        assert Enum.any?(spell.effects, &match?(%{aura: :periodic_trigger_spell, trigger_spell_id: ^trigger}, &1))
        assert Enum.any?(spell.effects, &(&1.amplitude_ms == 15_000))
        aura = SpellLoader.load(tracking)
        assert Enum.any?(aura.effects, &match?(%{aura: :dummy}, &1))
        world = WorldRef.instance(30, Unique.integer())

        character = %Character{
          object: %Object{guid: Unique.integer()},
          unit: %Unit{health: 100, auras: []},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          internal: %Internal{world: world}
        }

        context = %CastContext{
          spell: aura,
          caster_guid: Guid.from_low_guid(:mob, entry, Unique.integer()),
          caster_position: {world, 1.0, 0.0, 0.0}
        }

        {captured, _events} = Aura.apply_spell(character, context, aura, 0)
        assert Aura.has_spell?(captured, tracking)
        assert Aura.next_event_at(captured) == 2_000
      end
    end
  end
end
