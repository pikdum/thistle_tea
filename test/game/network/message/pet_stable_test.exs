defmodule ThistleTea.Game.Network.Message.PetStableTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet

  describe "stable packet dispatch" do
    test "decodes all five client operations" do
      for {opcode, module} <- [
            {0x26F, Message.MsgListStabledPetsClient},
            {0x270, Message.CmsgStablePet},
            {0x272, Message.CmsgBuyStableSlot}
          ] do
        assert Dispatch.to_message(Packet.build(<<123::little-64>>, opcode)) == struct!(module, guid: 123)
      end

      for {opcode, module} <- [{0x271, Message.CmsgUnstablePet}, {0x275, Message.CmsgStableSwapPet}] do
        assert Dispatch.to_message(Packet.build(<<123::little-64, 456::little-32>>, opcode)) ==
                 struct!(module, guid: 123, pet_number: 456)
      end
    end
  end

  describe "to_binary/1" do
    test "encodes the vanilla listing including loyalty and client slot" do
      pet = %{pet_number: 77, entry: 69, level: 20, name: "Wolf", loyalty: 3, slot: 2}
      packet = %Message.MsgListStabledPets{guid: 123, slots: 2, pets: [pet]}

      assert Message.MsgListStabledPets.to_binary(packet) ==
               <<123::little-64, 1, 2, 77::little-32, 69::little-32, 20::little-32, "Wolf", 0, 3::little-32, 2>>

      assert Message.MsgListStabledPets.to_binary(%{packet | pets: []}) == <<123::little-64, 0, 2>>
      assert Message.SmsgStableResult.to_binary(%Message.SmsgStableResult{result: 9}) == <<9>>
    end
  end
end
