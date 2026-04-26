defmodule ThistleTea.Game.Network.Message.SmsgMonsterMoveTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
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
