defmodule ThistleTea.Game.Entity.Server.PlayerFatigueMapsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.Corpses
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Terrain.Liquid
  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Loader.Graveyard
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Terrain

  @moduletag :namigator_maps

  describe "context/2" do
    test "stationary high-sea players exhaust from cached terrain and recover in coastal water" do
      character = %Character{
        object: %Object{guid: 98_025},
        player: %Player{},
        unit: %Unit{health: 1000, max_health: 1000, level: 1, auras: []},
        internal: %Internal{},
        movement_block: %MovementBlock{movement_flags: 0, position: {-10_000.0, 2500.0, 0.0, 0.0}}
      }

      context = AIEnvironment.context(character, 0)
      assert Liquid.high_sea?(context.terrain_liquid)
      {:running, tired} = BehaviorRunner.tick(PlayerBT.tree(), character, context)
      assert tired.internal.fatigue.remaining == 60_000
      {:running, exhausted} = BehaviorRunner.tick(PlayerBT.tree(), tired, AIEnvironment.context(tired, 60_000))
      assert exhausted.unit.health == 800

      coastal = %{exhausted | movement_block: %{exhausted.movement_block | position: {-10_000.0, 2400.0, 0.0, 0.0}}}
      recovering = Movement.apply_environment(coastal, :heartbeat, 61_000)
      assert recovering.unit.health == 800
      assert recovering.internal.fatigue.scale == 10

      {:running, recovered} =
        BehaviorRunner.tick(PlayerBT.tree(), recovering, AIEnvironment.context(recovering, 67_000))

      assert recovered.internal.fatigue == nil
    end
  end

  describe "liquid/2" do
    test "distinguishes inland water, coastal ocean, high sea and unavailable terrain" do
      assert %Liquid{flags: 8} = lake = Terrain.liquid(0, {-9500.0, -220.0, 55.47})
      assert_in_delta lake.surface, 57.631, 0.001
      assert_in_delta lake.floor, 55.4705, 0.001
      assert %Liquid{flags: 2} = Terrain.liquid(0, {-10_000.0, 2400.0, 0.0})
      assert %Liquid{flags: 18} = Terrain.liquid(0, {-10_000.0, 2500.0, 0.0})
      assert Terrain.liquid(9999, {0.0, 0.0, 0.0}) == nil
    end
  end

  describe "repop_at_graveyard/1" do
    test "rescues ghosts beyond navigation coverage using terrain exploration bits" do
      area = %AreaTable{id: 2364, map: 0, parent_area_table: 40, area_bit: 894}
      cache(Exploration, {:area, 2364}, area)
      cache(Exploration, {:area_bit, 0, 894}, 2364)
      cache(Graveyard, 40, [%{id: 900_001, map: 0, position: {-10_000.0, 1900.0, 10.0}, faction: 469}])
      cache(Graveyard, 2364, [])
      position = {-10_000.0, 3500.0, 0.0}
      assert Pathfinding.get_zone_and_area(0, position) == nil
      assert Terrain.zone_and_area(0, position) == {40, 2364}

      character = %Character{
        object: %Object{guid: 98_026},
        player: %Player{flags: 0x10},
        unit: %Unit{health: 1, max_health: 1000, level: 1, race: 1, auras: []},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {-10_000.0, 3500.0, 0.0, 0.0}}
      }

      state = Corpses.repop_at_graveyard(%State{guid: 98_026, ready: true, character: character})
      assert %{position: {-10_000.0, 1900.0, 10.0}, map: 0, token: token} = state.pending_repop
      assert_receive {:"$gen_cast", {:finish_repop, ^token}}
    end
  end

  defp cache(table, key, value) do
    previous = :ets.lookup(table, key)
    :ets.insert(table, {key, value})

    on_exit(fn ->
      :ets.delete(table, key)
      :ets.insert(table, previous)
    end)
  end
end
