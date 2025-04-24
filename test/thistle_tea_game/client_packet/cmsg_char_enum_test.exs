defmodule ThistleTeaGame.ClientPacket.CmsgCharEnumTest do
  use ExUnit.Case

  alias ThistleTeaGame.Effect
  alias ThistleTeaGame.Connection
  alias ThistleTeaGame.ClientPacket
  alias ThistleTeaGame.Message

  describe "handle/2" do
    test "returns a SMSG_CHAR_ENUM packet" do
      conn = %Connection{}
      packet = %Message.CmsgCharEnum{}

      {:ok, conn} = ClientPacket.Protocol.handle(packet, conn)
      [effect | _] = conn.effect_queue

      assert %Effect.SendPacket{
               packet: %Message.SmsgCharEnum{
                 characters: []
               }
             } == effect
    end
  end
end
