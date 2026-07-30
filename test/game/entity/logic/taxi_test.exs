defmodule ThistleTea.Game.Entity.Logic.TaxiTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Data.Taxi.Path
  alias ThistleTea.Game.Entity.Data.Taxi.PathNode
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Taxi

  describe "start/7" do
    test "charges the fare and enters a flying mounted spline" do
      token = make_ref()
      destination = node(4, {64.0, 0.0, 0.0})
      itinerary = itinerary()

      {character, effects} = Taxi.start(character(), itinerary, destination, 6852, token, 1_000)

      assert character.player.coinage == 75
      assert character.unit.mount_display_id == 6852
      assert (character.unit.flags &&& 0x00100004) == 0x00100004
      assert (character.movement_block.movement_flags &&& 0x01000000) != 0
      assert (character.movement_block.spline_flags &&& 0x00000200) != 0
      assert character.movement_block.duration == 2_000
      assert character.internal.movement_start_time == 1_000
      assert character.internal.taxi_flight.token == token
      assert character.internal.taxi_flight.path_ids == [12]
      assert [%Effects.MonsterMove{move_opts: [velocity: 32.0, flying?: true, run?: true]}] = effects
      assert character.internal.broadcast_update?
    end
  end

  describe "finish/2" do
    test "lands at the taxi node and restores player control" do
      token = make_ref()
      destination = node(4, {64.0, 0.0, 0.0})
      {character, _effects} = Taxi.start(character(), itinerary(), destination, 6852, token, 1_000)

      character = Taxi.finish(character, 1_500)

      assert character.movement_block.position == {64.0, 0.0, 0.0, 0.0}
      assert character.movement_block.spline_nodes == []
      assert character.movement_block.movement_flags == 0
      assert character.unit.mount_display_id == 0
      assert (character.unit.flags &&& 0x00100004) == 0
      refute Taxi.active?(character)
      assert character.internal.broadcast_update?
    end
  end

  defp character do
    %Character{
      unit: %Unit{flags: 0, mount_display_id: 0},
      player: %Player{coinage: 100},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{}
    }
  end

  defp itinerary do
    path = %Path{
      id: 12,
      source_node_id: 2,
      destination_node_id: 4,
      cost: 25,
      nodes: [
        %PathNode{index: 0, map_id: 0, position: {32.0, 0.0, 0.0}},
        %PathNode{index: 1, map_id: 0, position: {64.0, 0.0, 0.0}}
      ]
    }

    %{paths: [path], nodes: path.nodes, total_cost: 25}
  end

  defp node(id, position) do
    %Node{id: id, map_id: 0, position: position, name: "Node", mount_display_ids: %{alliance: 6852}}
  end
end
