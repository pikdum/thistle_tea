defmodule ThistleTea.Game.World.Loader.DazeDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Daze halves speed, refreshes, and expires through ordinary auras" do
      spell = SpellLoader.load(1604)
      assert spell.name == "Dazed"

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 30, auras: []},
        internal: %Internal{},
        movement_block: struct!(MovementBlock, MovementBlock.player_speeds())
      }

      context = %CastContext{caster_guid: 2, caster_level: 30, target_guid: 1, target_hostile?: true}
      {slowed, _events} = SpellEffect.receive(character, context, spell, 1_000)
      assert slowed.movement_block.run_speed == 3.5
      assert [holder] = slowed.unit.auras
      assert holder.expires_at == 5_000

      {refreshed, _events} = SpellEffect.receive(slowed, context, spell, 2_000)
      assert refreshed.movement_block.run_speed == 3.5
      assert [holder] = refreshed.unit.auras
      assert holder.expires_at == 6_000

      {restored, _events} = Aura.expire_due(refreshed, 6_000)
      assert restored.unit.auras == []
      assert restored.movement_block.run_speed == 7.0
    end
  end
end
