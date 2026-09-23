defmodule ThistleTea.Game.World.Loader.SpellStuckDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SafePosition
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "Stuck" do
    test "casts on the player and requests a teleport to the last safe position" do
      spell = SpellLoader.load(7355)
      assert [%{type: :stuck}] = spell.effects

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 60},
        player: %Player{},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.5}}
      }

      character = SafePosition.remember(character)
      character = %{character | movement_block: %{character.movement_block | position: {9.0, 9.0, -100.0, 0.5}}}
      assert SpellTargetResolver.resolve(character, spell, Target.unit(1)) == [1]

      context = %CastContext{caster_guid: 1, caster_level: 60, target_role: :caster}

      assert {^character, [%Effects.Teleport{position: {1.0, 2.0, 3.0, 0.5}}]} =
               SpellEffect.receive(character, context, spell, 1_000)
    end

    test ".start begins the unlearned recovery spell" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))

      character = %Character{
        object: %Object{guid: guid},
        unit: %Unit{health: 100, max_health: 100, level: 60, power1: 100, max_power1: 100, power_type: 0},
        player: %Player{},
        internal: %Internal{world: WorldRef.open(0), spellbook: %{}},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.5}}
      }

      character = SafePosition.remember(character)
      state = %State{guid: guid, packed_guid: BinaryUtils.pack_guid(guid), character: character}

      assert {:handled, started} = DevCommands.run(state, ".start")
      assert started.character.internal.casting.spell.id == 7355
      assert started.character.internal.casting.cast_time_ms == 10_000
    end
  end
end
