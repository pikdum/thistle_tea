defmodule ThistleTea.Game.Entity.EffectResolver.LeapTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps

  setup [:character]

  describe "resolve/2" do
    test "clips a leap on its forward line while preserving its world", %{character: character} do
      assert [%Effects.TeleportToWorld{world: world, position: {x, y, _z}, preserve_combat?: true}] =
               EffectResolver.resolve(character, Effects.leap({-8910.0, -150.0, 82.0, 0.0}))

      assert world == character.internal.world
      assert x > -8930.0 and x < -8920.0
      assert_in_delta y, -150.0, 0.05
    end

    test "supports creature targets through the same resolver", %{character: character} do
      mob = %Mob{unit: character.unit, internal: character.internal, movement_block: character.movement_block}
      request = Effects.leap({-8910.0, -150.0, 82.0, 0.0})
      assert EffectResolver.resolve(mob, request) == EffectResolver.resolve(character, request)
    end

    test "rejects taxi passengers", %{character: character} do
      character = %{character | internal: %{character.internal | taxi_flight: %{}}}
      assert EffectResolver.resolve(character, Effects.leap({-8910.0, -150.0, 82.0, 0.0})) == []
    end

    test "grounds falling leaps within forty yards", %{character: character} do
      movement = %{character.movement_block | position: {-8949.95, -132.49, 113.53, 0.0}, movement_flags: 0x4000}
      character = %{character | movement_block: movement}
      request = Effects.leap({-8969.95, -132.49, 113.53, 0.0})
      assert [%Effects.TeleportToWorld{position: {x, y, z}}] = EffectResolver.resolve(character, request)
      assert_in_delta x, -8969.95, 0.01
      assert_in_delta y, -132.49, 0.01
      assert_in_delta z, 83.29, 0.1

      character = %{character | movement_block: %{movement | movement_flags: 0}}
      assert EffectResolver.resolve(character, request) == []

      character = %{character | movement_block: %{movement | position: {-8949.95, -132.49, 133.53, 0.0}}}
      assert EffectResolver.resolve(character, Effects.leap({-8969.95, -132.49, 133.53, 0.0})) == []
    end

    test "retains submerged depth instead of snapping to the liquid mesh", %{character: character} do
      movement = %{character.movement_block | position: {-2180.0, -1867.59, -5.0, 0.0}, movement_flags: 0x200000}
      character = %{character | movement_block: movement}
      request = Effects.leap({-2160.0, -1867.59, -5.0, 0.0})

      assert [%Effects.TeleportToWorld{position: {-2160.0, -1867.59, -5.0}}] =
               EffectResolver.resolve(character, request)
    end
  end

  defp character(_context) do
    character = %Character{
      unit: %Unit{},
      internal: %Internal{world: WorldRef.instance(0, 42)},
      movement_block: %MovementBlock{position: {-8930.0, -150.0, 82.0, 0.0}, movement_flags: 0}
    }

    %{character: character}
  end
end
