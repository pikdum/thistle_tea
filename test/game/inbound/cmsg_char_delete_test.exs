defmodule ThistleTea.Game.Inbound.CmsgCharDeleteTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgCharDelete
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgCharDelete
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Test.Unique

  describe "handle/2" do
    test "decodes the character guid and reports a failed deletion of an unknown character" do
      guid = Unique.integer()
      packet = %Packet{opcode: Opcodes.get(:CMSG_CHAR_DELETE), payload: <<guid::little-64>>}
      assert %CmsgCharDelete{guid: ^guid} = message = Dispatch.to_message(packet)

      state = %{account: %{id: Unique.integer()}}
      assert Inbound.handle(message, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgCharDelete{result: 0x3A}}}
    end
  end
end
