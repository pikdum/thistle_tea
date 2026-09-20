defmodule ThistleTea.Game.Network.Message.CmsgMoveSplineDoneTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.CmsgMoveSplineDone
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes

  describe "from_binary/1" do
    test "decodes movement, the spline identifier, and the vanilla trailing float" do
      payload =
        <<0::little-size(32), 123::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 4.0::little-float-size(32), 0::little-size(32), 987::little-size(32),
          1.0::little-float-size(32)>>

      assert %CmsgMoveSplineDone{
               spline_id: 987,
               unknown: 1.0,
               movement_block: %MovementBlock{timestamp: 123, position: {1.0, 2.0, 3.0, 4.0}, fall_time: 0}
             } = CmsgMoveSplineDone.from_binary(payload)
    end

    test "keeps optional swimming data separate from the spline fields" do
      payload =
        <<0x200000::little-size(32), 123::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 4.0::little-float-size(32), 0.5::little-float-size(32), 0::little-size(32),
          987::little-size(32), 1.0::little-float-size(32)>>

      assert %CmsgMoveSplineDone{
               spline_id: 987,
               unknown: 1.0,
               movement_block: %MovementBlock{pitch: 0.5, fall_time: 0}
             } = CmsgMoveSplineDone.from_binary(payload)
    end
  end

  describe "handle/2" do
    test "ignores an unsolicited completion instead of accepting its position" do
      state = %State{}
      message = %CmsgMoveSplineDone{spline_id: 1, movement_block: %MovementBlock{position: {900.0, 0.0, 0.0, 0.0}}}

      assert CmsgMoveSplineDone.handle(message, state) == state
    end
  end

  describe "Dispatch.implemented?/1" do
    test "recognizes the spline completion opcode" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_MOVE_SPLINE_DONE))
    end
  end
end
