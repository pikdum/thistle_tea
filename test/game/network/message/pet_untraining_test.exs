defmodule ThistleTea.Game.Network.Message.PetUntrainingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet

  describe "pet untraining packets" do
    test "dispatches the pet GUID and encodes the quoted price" do
      guid = 0xF140000045000007
      assert Dispatch.to_message(Packet.build(<<guid::little-64>>, 0x2F0)) == %Message.CmsgPetUnlearn{pet_guid: guid}
      assert Message.SmsgPetUnlearnConfirm.opcode() == 0x2F1

      assert Message.SmsgPetUnlearnConfirm.to_binary(%Message.SmsgPetUnlearnConfirm{pet_guid: guid, cost: 5_000}) ==
               <<guid::little-64, 5_000::little-32>>
    end
  end
end
