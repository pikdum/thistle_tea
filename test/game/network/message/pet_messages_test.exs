defmodule ThistleTea.Game.Network.Message.PetMessagesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Metadata

  test "pet client messages are registered for dispatch" do
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_ACTION))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_NAME_QUERY))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_SET_ACTION))
  end

  describe "CMSG_PET_SET_ACTION" do
    test "decodes and dispatches an autocast toggle for an owned pet" do
      pet_guid = 123
      Entity.register(pet_guid)
      on_exit(fn -> Entity.unregister(pet_guid) end)
      data = 11_778 + Bitwise.bsl(0xC1, 24)

      message =
        Message.CmsgPetSetAction.from_binary(<<pet_guid::little-size(64), 3::little-size(32), data::little-size(32)>>)

      state = %{character: companion(:guardian, pet_guid)}

      assert Message.CmsgPetSetAction.handle(message, state) == state
      assert_receive {:pet_set_actions, [%{position: 3, action: 11_778, action_type: 0xC1}]}
    end

    test "dispatches action-bar changes to a charmed unit" do
      controlled_guid = 124
      Entity.register(controlled_guid)
      on_exit(fn -> Entity.unregister(controlled_guid) end)

      message = %Message.CmsgPetSetAction{
        pet_guid: controlled_guid,
        actions: [%{position: 3, action: 3110, action_type: 0xC1}]
      }

      state = %{character: companion(:charm, controlled_guid)}

      assert Message.CmsgPetSetAction.handle(message, state) == state
      assert_receive {:pet_set_actions, [%{action: 3110}]}
    end
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

      state = %{character: companion(:guardian, pet_guid)}

      assert Message.CmsgPetAction.handle(message, state) == state
      assert_receive {:pet_command, :follow, ^target_guid}
    end

    test "dispatches commands to a charmed unit" do
      controlled_guid = 124
      Entity.register(controlled_guid)
      on_exit(fn -> Entity.unregister(controlled_guid) end)

      message = %Message.CmsgPetAction{
        pet_guid: controlled_guid,
        action: 1,
        action_type: 0x07,
        target_guid: 0
      }

      state = %{character: companion(:charm, controlled_guid)}

      assert Message.CmsgPetAction.handle(message, state) == state
      assert_receive {:pet_command, :follow, 0}
    end

    test "rejects an attack command without a target" do
      pet_guid = 125
      Entity.register(pet_guid)
      on_exit(fn -> Entity.unregister(pet_guid) end)

      message = %Message.CmsgPetAction{pet_guid: pet_guid, action: 2, action_type: 0x07, target_guid: 0}
      state = %{character: companion(:guardian, pet_guid)}

      assert Message.CmsgPetAction.handle(message, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetActionFeedback{feedback: :nothing_to_attack}}}
      refute_receive {:pet_command, :attack, _target}, 10
    end

    test "rejects an attack command against an invalid target" do
      pet_guid = 126
      target_guid = 127
      Entity.register(pet_guid)
      Metadata.put(target_guid, %{alive?: false})

      on_exit(fn ->
        Entity.unregister(pet_guid)
        Metadata.delete(target_guid)
      end)

      message = %Message.CmsgPetAction{pet_guid: pet_guid, action: 2, action_type: 0x07, target_guid: target_guid}
      state = %{character: companion(:guardian, pet_guid)}

      assert Message.CmsgPetAction.handle(message, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetActionFeedback{feedback: :cant_attack_target}}}
      refute_receive {:pet_command, :attack, _target}, 10
    end
  end

  describe "SMSG_PET_ACTION_FEEDBACK" do
    test "encodes the feedback code as a single byte" do
      assert Message.SmsgPetActionFeedback.to_binary(Message.SmsgPetActionFeedback.new(:pet_dead)) == <<1>>
      assert Message.SmsgPetActionFeedback.to_binary(Message.SmsgPetActionFeedback.new(:nothing_to_attack)) == <<2>>
      assert Message.SmsgPetActionFeedback.to_binary(Message.SmsgPetActionFeedback.new(:cant_attack_target)) == <<3>>
      assert Message.SmsgPetActionFeedback.to_binary(Message.SmsgPetActionFeedback.new(:no_path_to)) == <<4>>
    end
  end

  describe "SMSG_PET_CAST_FAILED" do
    test "encodes spell id, fail status, and reason code" do
      message = %Message.SmsgPetCastFailed{spell_id: 6358, reason: :bad_targets}

      assert Message.SmsgPetCastFailed.to_binary(message) == <<6358::little-size(32), 2, 0x0A>>
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

    test "accepts loaded spellbook entries" do
      message = Message.SmsgPetSpells.for_pet(123, [%Spell{id: 11_778}])

      assert length(message.spells) == 1
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

    test "generic name queries tolerate pet metadata without player fields" do
      pet_guid = 456
      Metadata.put(pet_guid, %{name: "Voidwalker"})
      on_exit(fn -> Metadata.delete(pet_guid) end)

      state = %{}
      assert Message.CmsgNameQuery.handle(%Message.CmsgNameQuery{guid: pet_guid}, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgNameQueryResponse{character_name: "Voidwalker"}}}
    end
  end

  defp companion(kind, guid) do
    %Character{unit: %Unit{}, internal: %Internal{}}
    |> Companion.activate(kind, %EntityRef{guid: guid, entry: 1, spell_id: 1})
  end
end
