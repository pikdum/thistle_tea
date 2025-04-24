defmodule ThistleTeaGame.ClientPacket.CmsgCharEnumTest do
  use ExUnit.Case

  alias ThistleTeaGame.Effect
  alias ThistleTeaGame.Connection
  alias ThistleTeaGame.ClientPacket
  alias ThistleTeaGame.ServerPacket

  describe "handle/2" do
    test "returns a SMSG_CHAR_ENUM packet" do
      conn = %Connection{}
      packet = %ClientPacket.CmsgCharEnum{}

      {:ok, conn} = ClientPacket.CmsgCharEnum.handle(packet, conn)
      [effect | _] = conn.effect_queue

      assert %Effect.SendPacket{
               packet: %ServerPacket.SmsgCharEnum{
                 characters: []
               }
             } == effect
    end
  end
end
