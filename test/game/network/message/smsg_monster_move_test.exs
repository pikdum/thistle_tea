defmodule ThistleTea.Game.Network.Message.SmsgMonsterMoveTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove

  describe "build/2" do
    test "adds runmode for monster move spline flags" do
      msg =
        build_entity(spline_flags: 0)
        |> SmsgMonsterMove.build()

      assert msg.spline_flags == 0x100
    end

    test "keeps final facing out of monster move spline flags" do
      msg =
        build_entity(spline_flags: 0x00020000)
        |> SmsgMonsterMove.build(face_target: 2)

      assert msg.move_type == 3
      assert msg.target == 2
      assert msg.spline_flags == 0x100
    end

    test "encodes a final facing angle" do
      msg =
        build_entity(spline_flags: 0)
        |> SmsgMonsterMove.build(face_angle: 1.5)

      assert msg.move_type == 4
      assert msg.angle == 1.5
    end

    test "prefers a facing target over a facing angle" do
      msg =
        build_entity(spline_flags: 0)
        |> SmsgMonsterMove.build(face_target: 7, face_angle: 1.5)

      assert msg.move_type == 3
      assert msg.target == 7
    end

    test "encodes flying splines as full Catmull-Rom points" do
      msg =
        build_entity(spline_flags: 0x200)
        |> then(&%{&1 | movement_block: %{&1.movement_block | spline_nodes: [{1.0, 2.0, 3.0}, {4.0, 5.0, 6.0}]}})
        |> SmsgMonsterMove.build()

      assert (msg.spline_flags &&& 0x200) != 0

      guid = BinaryUtils.pack_guid(1)

      assert SmsgMonsterMove.to_binary(msg) ==
               guid <>
                 <<
                   0.0::little-float-size(32),
                   0.0::little-float-size(32),
                   0.0::little-float-size(32),
                   5::little-size(32),
                   0::little-size(8),
                   0x300::little-size(32),
                   100::little-size(32),
                   2::little-size(32),
                   1.0::little-float-size(32),
                   2.0::little-float-size(32),
                   3.0::little-float-size(32),
                   4.0::little-float-size(32),
                   5.0::little-float-size(32),
                   6.0::little-float-size(32)
                 >>
    end
  end

  defp build_entity(opts) do
    %{
      object: %Object{guid: 1},
      movement_block: %MovementBlock{
        position: {0.0, 0.0, 0.0, 0.0},
        spline_nodes: [{1.0, 0.0, 0.0}],
        duration: 100,
        spline_flags: Keyword.fetch!(opts, :spline_flags)
      },
      internal: %Internal{spline_id: 5}
    }
  end
end
