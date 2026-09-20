defmodule ThistleTea.Game.Network.Message.CmsgTogglePvpTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgTogglePvp
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet

  describe "from_binary/1" do
    test "decodes both vanilla forms through packet dispatch" do
      assert %CmsgTogglePvp{enabled: :toggle} = Dispatch.to_message(%Packet{opcode: 0x253, payload: <<>>})
      assert %CmsgTogglePvp{enabled: true} = Dispatch.to_message(%Packet{opcode: 0x253, payload: <<1>>})
      assert %CmsgTogglePvp{enabled: false} = Dispatch.to_message(%Packet{opcode: 0x253, payload: <<0>>})
    end

    test "rejects malformed states without treating them as a toggle" do
      assert %CmsgTogglePvp{enabled: nil} = CmsgTogglePvp.from_binary(<<2>>)
      assert %CmsgTogglePvp{enabled: nil} = CmsgTogglePvp.from_binary(<<1, 0>>)
    end
  end

  describe "handle/2" do
    test "ignores requests before entering the world" do
      state = %{ready: false}
      assert CmsgTogglePvp.handle(%CmsgTogglePvp{enabled: :toggle}, state) == state
    end
  end
end
