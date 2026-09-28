defmodule ThistleTea.Game.World.Loader.SpellPostureDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Posture
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "allows seated food and drink while retaining movement requirements" do
      seated = %Character{unit: %Unit{stand_state: 1}, movement_block: %MovementBlock{movement_flags: 0}}
      moving = %{seated | movement_block: %{seated.movement_block | movement_flags: 1}}

      for id <- [430, 433] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :allow_while_sitting)
        assert Posture.validate(seated, spell) == :ok
        assert Posture.validate(moving, spell) == {:error, :moving}
      end

      for id <- [133, 11_366, 1159] do
        spell = SpellLoader.load(id)
        refute Spell.attribute?(spell, :allow_while_sitting)
        assert Posture.validate(seated, spell) == {:error, :not_standing}
      end
    end
  end
end
