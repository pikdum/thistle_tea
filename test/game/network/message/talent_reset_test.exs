defmodule ThistleTea.Game.Network.Message.TalentResetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet

  describe "talent reset packets" do
    test "dispatches the trainer GUID and encodes the price on the shared opcode" do
      guid = 0xF13000158B000007

      assert Dispatch.to_message(Packet.build(<<guid::little-64>>, 0x2AA)) == %Message.MsgTalentWipeConfirmClient{
               trainer_guid: guid
             }

      assert Message.MsgTalentWipeConfirm.opcode() == 0x2AA

      assert Message.MsgTalentWipeConfirm.to_binary(%Message.MsgTalentWipeConfirm{trainer_guid: guid, cost: 50_000}) ==
               <<guid::little-64, 50_000::little-32>>

      assert Message.MsgTalentWipeConfirm.to_binary(%Message.MsgTalentWipeConfirm{}) == <<0::little-64, 0::little-32>>
    end
  end
end
