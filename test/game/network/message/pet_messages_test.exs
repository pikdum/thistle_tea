defmodule ThistleTea.Game.Network.Message.PetMessagesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes

  test "pet client messages are registered for dispatch" do
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_ACTION))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_NAME_QUERY))
  end

  describe "CMSG_PET_ACTION" do
    test "decodes and dispatches an owned pet follow command" do
      pet_guid = 123
      target_guid = 0
      Entity.register(pet_guid)
      on_exit(fn -> Entity.unregister(pet_guid) end)

      data = 1 + Bitwise.bsl(0x07, 24)

      message =
        Message.CmsgPetAction.from_binary(
          <<pet_guid::little-size(64), data::little-size(32), target_guid::little-size(64)>>
        )

      state = %{character: %Character{unit: %Unit{summon: pet_guid}}}

      assert Message.CmsgPetAction.handle(message, state) == state
      assert_receive {:pet_command, :follow, ^target_guid}
    end
  end

  describe "SMSG_PET_SPELLS" do
    test "encodes the vanilla action bar and known spell list" do
      message = Message.SmsgPetSpells.for_pet(123, [%CreatureSpell{spell_id: 3110}])
      binary = Message.SmsgPetSpells.to_binary(message)

      assert byte_size(binary) == 62
      assert <<123::little-size(64), 0::little-size(32), 1::little-size(8), 1::little-size(8), _::binary>> = binary
    end

    test "encodes the clear-pet form as a zero guid" do
      assert Message.SmsgPetSpells.clear() |> Message.SmsgPetSpells.to_binary() == <<0::little-size(64)>>
    end
  end

  describe "pet name messages" do
    test "decodes the query and encodes the vanilla name response" do
      query = Message.CmsgPetNameQuery.from_binary(<<77::little-size(32), 123::little-size(64)>>)
      assert query.pet_number == 77
      assert query.pet_guid == 123

      response = %Message.SmsgPetNameQueryResponse{pet_number: 77, name: "Imp", timestamp: 99}

      assert Message.SmsgPetNameQueryResponse.to_binary(response) ==
               <<77::little-size(32), "Imp", 0, 99::little-size(32)>>
    end
  end
end
