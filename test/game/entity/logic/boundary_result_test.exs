defmodule ThistleTea.Game.Entity.Logic.BoundaryResultTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.BoundaryResult

  describe "apply/2" do
    test "applies a resolved charge path atomically" do
      character = %Character{movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}}

      command = %Commands.ChargePathResolved{
        path: [{2.0, 0.0, 0.0}],
        duration_ms: 80,
        destination: {2.0, 0.0, 0.0, 0.5}
      }

      character = BoundaryResult.apply(character, command)

      assert character.movement_block.spline_nodes == [{2.0, 0.0, 0.0}]
      assert character.movement_block.duration == 80
      assert character.movement_block.spline_flags == 0x100
      assert character.movement_block.position == {2.0, 0.0, 0.0, 0.5}
    end

    test "records a started farsight object" do
      character = %Character{player: %Player{}, internal: %Internal{}}

      character = BoundaryResult.apply(character, %Commands.FarsightStarted{guid: 55})

      assert character.player.farsight == 55
      assert character.internal.broadcast_update?
    end

    test "records an owned ritual object" do
      character = %Character{unit: %Unit{}, internal: %Internal{}}

      character = BoundaryResult.apply(character, %Commands.ChannelGameObjectStarted{guid: 77})

      assert character.unit.channel_object == 77
      assert character.internal.channel_game_object_guid == 77
      assert character.internal.channel_game_object_owned?
      assert character.internal.broadcast_update?
    end

    test "records a started totem by slot" do
      character = %Character{internal: %Internal{totem_guids: %{1 => 10}}}

      character = BoundaryResult.apply(character, %Commands.TotemStarted{slot: 1, guid: 20})

      assert character.internal.totem_guids == %{1 => 20}
    end
  end
end
