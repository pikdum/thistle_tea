defmodule ThistleTea.Game.Network.Message.CmsgFarSightTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgFarSight
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet

  describe "from_binary/1" do
    test "decodes the camera operation and is registered" do
      assert CmsgFarSight.from_binary(<<0>>) == %CmsgFarSight{operation: 0}
      assert CmsgFarSight.from_binary(<<1>>) == %CmsgFarSight{operation: 1}
      assert %CmsgFarSight{operation: 1} = Dispatch.to_message(%Packet{opcode: 0x27A, payload: <<1>>})
    end
  end
end
