defmodule ThistleTea.Game.World.LiquidSpellMapsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Terrain.Liquid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Player.Movement

  @moduletag :namigator_maps

  describe "terrain_liquid/1" do
    test "retains the Naxxramas spell-bearing slime entry above its real floor" do
      character = %Character{
        internal: %Internal{world: WorldRef.instance(533, 42)},
        movement_block: %MovementBlock{position: {3050.0, -3175.0, 293.5, 0.0}}
      }

      assert %Liquid{entry: 21, flags: 4, surface: surface, floor: floor} =
               liquid =
               Movement.terrain_liquid(character)

      assert_in_delta surface, 293.68494, 0.001
      assert_in_delta floor, 293.34515, 0.001
      assert Liquid.spell_id(liquid, 293.5) == 28_801
      assert Liquid.spell_id(liquid, surface) == nil

      buried = %{character | movement_block: %{character.movement_block | position: {3050.0, -3175.0, 290.0, 0.0}}}
      assert Movement.terrain_liquid(buried) == nil
    end
  end
end
