defmodule ThistleTea.Game.Network.Message.CmsgForceMoveRootAckTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Network.Message.CmsgForceMoveRootAck
  alias ThistleTea.Game.Network.Message.CmsgForceMoveUnrootAck
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes

  describe "from_binary/1" do
    test "parses force root acknowledgements" do
      payload = ack_payload(1, 2)
      movement_payload = movement_payload()

      assert %CmsgForceMoveRootAck{guid: 1, counter: 2, movement_payload: ^movement_payload} =
               CmsgForceMoveRootAck.from_binary(payload)
    end

    test "parses force unroot acknowledgements" do
      payload = ack_payload(3, 4)
      movement_payload = movement_payload()

      assert %CmsgForceMoveUnrootAck{guid: 3, counter: 4, movement_payload: ^movement_payload} =
               CmsgForceMoveUnrootAck.from_binary(payload)
    end
  end

  describe "handle/2" do
    test "updates movement state from force root acknowledgements" do
      state = ack_state()

      state = CmsgForceMoveRootAck.handle(%CmsgForceMoveRootAck{movement_payload: movement_payload()}, state)

      assert state.character.movement_block.position == {1.0, 2.0, 3.0, 4.0}
      assert state.character.movement_block.run_speed == 7.0
    end

    test "updates movement state from force unroot acknowledgements" do
      state = ack_state()

      state = CmsgForceMoveUnrootAck.handle(%CmsgForceMoveUnrootAck{movement_payload: movement_payload()}, state)

      assert state.character.movement_block.position == {1.0, 2.0, 3.0, 4.0}
      assert state.character.movement_block.run_speed == 7.0
    end
  end

  describe "Dispatch.implemented?/1" do
    test "recognizes force root acknowledgement opcodes" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_FORCE_MOVE_ROOT_ACK))
      assert Dispatch.implemented?(Opcodes.get(:CMSG_FORCE_MOVE_UNROOT_ACK))
    end
  end

  defp ack_payload(guid, counter) do
    <<guid::little-size(64), counter::little-size(32)>> <> movement_payload()
  end

  defp movement_payload do
    <<0::little-size(32), 123::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
      3.0::little-float-size(32), 4.0::little-float-size(32), 0::little-size(32)>>
  end

  defp ack_state do
    %{character: %Character{movement_block: %MovementBlock{run_speed: 7.0}}}
  end
end
