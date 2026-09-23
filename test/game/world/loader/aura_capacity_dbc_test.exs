defmodule ThistleTea.Game.World.Loader.AuraCapacityDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.Priority
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "real class debuffs retain their reference priority" do
      for {id, priority} <- [
            {1776, 1},
            {703, 2},
            {772, 2},
            {408, 3},
            {99, 4},
            {116, 3},
            {118, 0},
            {172, 2},
            {589, 2},
            {1490, 3},
            {6136, 4}
          ] do
        spell = SpellLoader.load(id)
        auras = Enum.map(spell.effects, &%AuraData{type: &1.aura})
        assert Priority.value(%Holder{spell: spell, auras: auras, negative?: true}, 1) == priority
      end
    end

    test "Blizzard is exempt while Hurricane's attack-speed debuff requires a slot" do
      refute UnitSync.visible?(SpellLoader.load(10))
      assert UnitSync.visible?(SpellLoader.load(16_914))
    end
  end
end
