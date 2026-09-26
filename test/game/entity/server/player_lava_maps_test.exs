defmodule ThistleTea.Game.Entity.Server.PlayerLavaMapsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Terrain.Liquid
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Terrain

  @moduletag :namigator_maps

  describe "terrain_liquid/1" do
    test "samples Blackrock Mountain lava separately from bridges and buried terrain" do
      character = character({-7580.0, -1140.0, 167.2, 0.0})
      assert Terrain.liquid(0, {-7580.0, -1140.0, 167.2}) == nil
      assert %Liquid{entry: 3, flags: 1, surface: surface, floor: floor} = Movement.terrain_liquid(character)
      assert_in_delta surface, 168.448, 0.01
      assert_in_delta floor, 148.490, 0.01
      assert Pathfinding.wmo_liquid(0, {-7580.0, -1140.0, 239.0}) == nil
      assert Pathfinding.wmo_liquid(0, {-7580.0, -1140.0, 145.0}) == nil
      assert Pathfinding.wmo_liquid(9999, {0.0, 0.0, 0.0}) == nil
    end
  end

  describe "context/2" do
    test "movement and stationary ticks burn in outdoor and WMO lava" do
      for position <- [{-7483.3333, -850.0, 265.7, 0.0}, {-7580.0, -1140.0, 167.2, 0.0}] do
        character = character(position)
        entered = Movement.apply_environment(character, :heartbeat, 0)
        assert entered.internal.lava_exposure.remaining == 1000
        assert entered.unit.health == 3000
        {:running, burned} = BehaviorRunner.tick(PlayerBT.tree(), entered, AIEnvironment.context(entered, 1000))
        assert burned.unit.health in 2390..2395
        assert Enum.any?(burned.internal.events, &match?(%Effects.EnvironmentalDamage{type: :lava}, &1))

        escaped = %{burned | movement_block: %{burned.movement_block | position: {-8949.95, -132.49, 83.53, 0.0}}}
        escaped = Movement.apply_environment(escaped, :heartbeat, 3000)
        assert escaped.internal.lava_exposure == nil
        assert escaped.unit.health == burned.unit.health
      end
    end
  end

  defp character(position) do
    %Character{
      object: %Object{guid: 98_027},
      player: %Player{},
      unit: %Unit{health: 3000, max_health: 3000, level: 60, auras: [], fire_resistance: 0},
      internal: %Internal{},
      movement_block: %MovementBlock{movement_flags: 0, position: position}
    }
  end
end
