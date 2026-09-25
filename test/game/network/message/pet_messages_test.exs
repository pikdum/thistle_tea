defmodule ThistleTea.Game.Network.Message.PetMessagesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef
  alias ThistleTea.Test.PetControlOwner

  describe "SMSG_PET_BROKEN" do
    test "encodes the empty vanilla notification" do
      assert Message.SmsgPetBroken.to_binary(%Message.SmsgPetBroken{}) == <<>>
      assert Message.SmsgPetBroken.opcode() == Opcodes.get(:SMSG_PET_BROKEN)
    end
  end

  test "pet client messages are registered for dispatch" do
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_ACTION))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_STOP_ATTACK))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_CANCEL_AURA))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_CAST_SPELL))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_NAME_QUERY))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_RENAME))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_ABANDON))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_SET_ACTION))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_PET_SPELL_AUTOCAST))
    assert Dispatch.implemented?(Opcodes.get(:CMSG_REQUEST_PET_INFO))
  end

  describe "CMSG_PET_STOP_ATTACK" do
    test "dispatches to an owned creature and a possessed player" do
      guid = Guid.from_low_guid(:mob, 1, 131)
      Entity.register(guid)
      message = Message.CmsgPetStopAttack.from_binary(<<guid::little-size(64)>>)
      state = %{character: companion(:guardian, guid)}
      assert Message.CmsgPetStopAttack.handle(message, state) == state
      assert_receive {:pet_stop_attack, 7}
      stranger = %{state | character: companion(:guardian, guid + 1)}
      assert Message.CmsgPetStopAttack.handle(message, stranger) == stranger
      refute_receive {:pet_stop_attack, _}, 0
      player = Guid.from_low_guid(:player, 132)
      Entity.register(player)
      state = %{character: companion(:possession, player)}
      assert Message.CmsgPetStopAttack.handle(%{message | pet_guid: player}, state) == state
      assert_receive {:controlled_command, 7, :stop_attack, 0}
    end
  end

  describe "CMSG_PET_CANCEL_AURA" do
    test "decodes pet aura cancellation and rejects remote possession or a different pet" do
      guid = Guid.from_low_guid(:mob, 1, 133)
      Entity.register(guid)
      message = Message.CmsgPetCancelAura.from_binary(<<guid::little-size(64), 11_767::little-size(32)>>)
      state = %{character: companion(:guardian, guid)}
      assert Message.CmsgPetCancelAura.handle(message, state) == state
      assert_receive {:pet_cancel_aura, 7, 11_767}

      for character <- [companion(:possession, guid), companion(:guardian, guid + 1)] do
        state = %{character: character}
        assert Message.CmsgPetCancelAura.handle(message, state) == state
      end

      remote = Map.put(state, :active_mover_guid, guid)
      assert Message.CmsgPetCancelAura.handle(message, remote) == remote
      refute_receive {:pet_cancel_aura, _, _}, 0
    end
  end

  describe "CMSG_PET_CAST_SPELL" do
    test "preserves a charmed creature's explicit destination" do
      guid = Guid.from_low_guid(:mob, 1, 128)
      Entity.register(guid)
      on_exit(fn -> Entity.unregister(guid) end)
      targets = Target.at({12.5, -8.0, 3.0})
      payload = <<guid::little-size(64), 19_717::little-size(32)>> <> TargetCodec.encode(targets)
      message = Message.CmsgPetCastSpell.from_binary(payload)
      character = companion(:charm, guid)
      state = %{character: character}

      assert Message.CmsgPetCastSpell.handle(message, state) == state
      controller = character.object.guid
      assert_receive {:pet_cast, ^controller, 19_717, ^targets}
    end

    test "decodes self selection relative to the pet and rejects an unowned creature" do
      guid = Guid.from_low_guid(:mob, 1, 129)
      Entity.register(guid)
      on_exit(fn -> Entity.unregister(guid) end)
      message = Message.CmsgPetCastSpell.from_binary(<<guid::little-size(64), 3110::little-size(32), 0::16>>)
      state = %{character: companion(:guardian, guid)}

      assert Message.CmsgPetCastSpell.handle(message, state) == state
      assert_receive {:pet_cast, _, 3110, %Target{selection: {:self, ^guid}}}
      stranger = %{state | character: companion(:guardian, guid + 1)}
      assert Message.CmsgPetCastSpell.handle(message, stranger) == stranger
      refute_receive {:pet_cast, _, _, _}, 0
    end
  end

  describe "CMSG_REQUEST_PET_INFO" do
    test "decodes the empty request and reuses the active companion attachment handshake" do
      pet_guid = Guid.from_low_guid(:mob, 1, 123)
      Entity.register(pet_guid)
      on_exit(fn -> Entity.unregister(pet_guid) end)

      message = Message.CmsgRequestPetInfo.from_binary(<<>>)
      state = %{ready: true, character: companion(:hunter_pet, pet_guid)}

      assert Message.CmsgRequestPetInfo.handle(message, state) == state
      assert_receive {:attach_pet, owner_pid, 1, nil}
      assert owner_pid == self()
    end

    test "does not start a second summon while initial restoration is pending" do
      message = Message.CmsgRequestPetInfo.from_binary(<<>>)

      character =
        %Character{unit: %Unit{health: 100}, internal: %Internal{}}
        |> Companion.suspend_as(:hunter_pet, 2960, 1515)

      state = %{ready: true, character: character}

      assert Message.CmsgRequestPetInfo.handle(message, state) == state
      refute_receive {:attach_pet, _owner_pid, _spell_id, _spells}, 10
    end
  end

  describe "CMSG_PET_SET_ACTION" do
    test "decodes and dispatches an autocast toggle for an owned pet" do
      pet_guid = Guid.from_low_guid(:mob, 1, 123)
      Entity.register(pet_guid)
      on_exit(fn -> Entity.unregister(pet_guid) end)
      Entity.unregister(pet_guid)
      start_supervised!({PetControlOwner, guid: pet_guid, spells: [%Spell{id: 11_778}]})
      data = 11_778 + Bitwise.bsl(0xC1, 24)

      message =
        Message.CmsgPetSetAction.from_binary(<<pet_guid::little-size(64), 3::little-size(32), data::little-size(32)>>)

      state = %{character: companion(:guardian, pet_guid)}

      updated = Message.CmsgPetSetAction.handle(message, state)
      assert Companion.autocast(updated.character) == MapSet.new([11_778])
      assert Companion.relationship(updated.character).action_bar[3] == {11_778, 0xC1}
    end

    test "dispatches action-bar changes to a charmed unit" do
      controlled_guid = Guid.from_low_guid(:mob, 1, 124)
      Entity.register(controlled_guid)
      on_exit(fn -> Entity.unregister(controlled_guid) end)

      message = %Message.CmsgPetSetAction{
        pet_guid: controlled_guid,
        actions: [%{position: 3, action: 3110, action_type: 0xC1}]
      }

      state = %{character: companion(:charm, controlled_guid)}

      Entity.unregister(controlled_guid)
      start_supervised!({PetControlOwner, guid: controlled_guid, spells: [%Spell{id: 3110}]})
      updated = Message.CmsgPetSetAction.handle(message, state)
      assert Companion.autocast(updated.character) == MapSet.new([3110])
    end
  end

  describe "CMSG_PET_SPELL_AUTOCAST" do
    test "saves only settings accepted by the current creature owner" do
      guid = Guid.from_low_guid(:mob, 1, 127)
      start_supervised!({PetControlOwner, guid: guid, spells: [%Spell{id: 3110}]})
      state = %{character: companion(:guardian, guid)}
      message = Message.CmsgPetSpellAutocast.from_binary(<<guid::little-size(64), 3110::little-size(32), 1>>)
      updated = Message.CmsgPetSpellAutocast.handle(message, state)
      assert Companion.autocast(updated.character) == MapSet.new([3110])
      assert Companion.relationship(updated.character).action_bar[3] == {3110, 0xC1}
      invalid = %{message | spell_id: 999}
      assert Message.CmsgPetSpellAutocast.handle(invalid, updated) == updated
      stranger = %{state | character: companion(:guardian, guid + 1)}
      assert Message.CmsgPetSpellAutocast.handle(message, stranger) == stranger
      disabled = Message.CmsgPetSpellAutocast.handle(%{message | enabled?: false}, updated)
      assert Companion.autocast(disabled.character) == MapSet.new()
    end
  end

  describe "CMSG_PET_ACTION" do
    test "decodes and dispatches an owned pet follow command" do
      pet_guid = Guid.from_low_guid(:mob, 1, 123)
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
      controlled_guid = Guid.from_low_guid(:mob, 1, 124)
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
    test "includes passive spells beyond the four active buttons" do
      active = Enum.map(1..4, &%Spell{id: &1})
      passive = Enum.map(5..8, &%Spell{id: &1, attributes: MapSet.new([:passive])})
      message = Message.SmsgPetSpells.for_pet(123, passive ++ active)
      binary = Message.SmsgPetSpells.to_binary(message)
      assert <<_header_and_bar::binary-size(56), 8, known::binary-size(32), 0>> = binary

      assert for(<<id::little-size(24), type::size(8) <- known>>, do: {id, type}) ==
               Enum.map(1..4, &{&1, 0x81}) ++ Enum.map(5..8, &{&1, 0x01})

      assert Enum.map(Enum.slice(message.action_bars, 3, 4), &Bitwise.band(&1, 0xFFFFFF)) == [1, 2, 3, 4]
    end

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

    test "marks persisted autocast spells enabled" do
      message = Message.SmsgPetSpells.for_pet(123, [%Spell{id: 11_778}], MapSet.new([11_778]))

      assert [encoded_spell] = message.spells
      assert Bitwise.bsr(encoded_spell, 24) == 0xC1
      assert Enum.any?(message.action_bars, &(Bitwise.band(&1, 0x00FFFFFF) == 11_778 and Bitwise.bsr(&1, 24) == 0xC1))
    end
  end

  describe "pet name messages" do
    test "decodes a vanilla rename and encodes the empty invalid-name reply" do
      assert Message.CmsgPetRename.from_binary(<<123::little-size(64), "Fang", 0>>) ==
               %Message.CmsgPetRename{pet_guid: 123, name: "Fang"}

      assert Message.SmsgPetNameInvalid.to_binary(%Message.SmsgPetNameInvalid{}) == <<>>
      assert Message.SmsgPetNameInvalid.opcode() == Opcodes.get(:SMSG_PET_NAME_INVALID)
      assert Message.CmsgPetAbandon.from_binary(<<123::little-size(64)>>) == %Message.CmsgPetAbandon{pet_guid: 123}
    end

    test "responds with the published name timestamp and validates the pet number" do
      pet_guid = Guid.from_low_guid(:mob, 1, 123)
      Metadata.put(pet_guid, %{name: "Wolf", owner_guid: 7, pet_number: 77, pet_name_timestamp: 99})
      SpatialHash.update(:players, pet_guid, WorldRef.open(0), 0.0, 0.0, 0.0)

      on_exit(fn ->
        Metadata.delete(pet_guid)
        SpatialHash.remove(:players, pet_guid)
      end)

      state = %{ready: true, guid: 7, character: companion(:hunter_pet, pet_guid)}
      query = %Message.CmsgPetNameQuery{pet_number: 77, pet_guid: pet_guid}
      assert Message.CmsgPetNameQuery.handle(query, state) == state

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgPetNameQueryResponse{pet_number: 77, name: "Wolf", timestamp: 99}}}

      assert Message.CmsgPetNameQuery.handle(%{query | pet_number: 78}, state) == state
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetNameQueryResponse{}}}

      observer = %{state | guid: 8, character: Companion.clear(state.character)}
      observer = put_in(observer.character.object.guid, 8)
      assert Message.CmsgPetNameQuery.handle(query, observer) == observer
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetNameQueryResponse{name: "Wolf"}}}

      SpatialHash.update(:players, pet_guid, WorldRef.instance(0, 1), 0.0, 0.0, 0.0)
      assert Message.CmsgPetNameQuery.handle(query, observer) == observer
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetNameQueryResponse{}}}
    end

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
    %Character{
      object: %Object{guid: 7},
      unit: %Unit{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{}
    }
    |> Companion.activate(kind, %EntityRef{guid: guid, entry: 1, spell_id: 1})
  end
end
