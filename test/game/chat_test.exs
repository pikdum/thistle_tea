defmodule ThistleTea.Game.ChatTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Chat
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.ChatStatus
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  describe "handle/5" do
    test "whispers deliver tagged text, sender echoes and current availability replies" do
      sender = state(unique_guid(), "Sender")
      receiver = state(unique_guid(), "Receiver")
      {:ok, _} = EntityRegistry.register(sender.guid)
      {:ok, _} = EntityRegistry.register(receiver.guid)
      on_exit(fn -> Presence.leave(receiver.character) end)

      sender = %{sender | character: ChatStatus.change(sender.character, :dnd, "Busy")}

      for {mode, type, tag} <- [{:afk, 0x14, 1}, {:dnd, 0x15, 2}] do
        away = ChatStatus.change(receiver.character, mode, "Café break")
        Presence.enter(away, %{name: "Receiver"})
        assert Chat.handle(sender, 6, 7, "Hello", "receiver") == sender

        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 6, tag: 2, language: 0}}}
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 7, tag: ^tag}}}

        assert_receive {:"$gen_cast",
                        {:send_packet, %Message.SmsgMessagechat{chat_type: ^type, message: "Café break", tag: 0}}}
      end

      Presence.sync(receiver.character, %{})
      Chat.handle(sender, 6, 7, "Available", "Receiver")
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 6}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 7, tag: 0}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{}}}
    end

    test "missing whisper recipients return an error without confirmation" do
      state = state(unique_guid(), "Sender")
      Chat.handle(state, 6, 7, "Hello", "Absent#{unique_guid()}")
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgChatPlayerNotFound{}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{}}}
    end

    test "routes availability commands through the player owner" do
      state = state(unique_guid(), "Away")
      afk = Chat.handle(state, 0x14, 0, "Tea", nil)
      assert afk.character.internal.chat_status.mode == :afk
      assert afk.character.player.flags == 2
      dnd = Chat.handle(afk, 0x15, 0, "Busy", nil)
      assert dnd.character.player.flags == 4
      assert Chat.handle(dnd, 0x15, 0, "", nil).character.player.flags == 0
    end

    test "routes party chat through party membership" do
      first = unique_guid()
      second = unique_guid()
      {:ok, _owner} = EntityRegistry.register(first)
      {:ok, _owner} = EntityRegistry.register(second)
      :ok = PartySystem.invite(first, "First", second)
      {:ok, _group} = PartySystem.accept(second, "Second")

      state = state(first, "First")
      assert Chat.handle(state, 0x01, 7, "party only", nil) == state

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 0x01, message: "party only"}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 0x01, message: "party only"}}}

      {:ok, _outcome} = PartySystem.leave(first)
      EntityRegistry.unregister(first)
      EntityRegistry.unregister(second)
    end

    test "restricts party chat to the subgroup and authorizes raid leadership channels" do
      [first, second, third] = guids = for _ <- 1..3, do: unique_guid()
      Enum.each(guids, &EntityRegistry.register/1)
      :ok = PartySystem.invite(first, "First", second)
      {:ok, _} = PartySystem.accept(second, "Second")
      :ok = PartySystem.invite(first, "First", third)
      {:ok, _} = PartySystem.accept(third, "Third")
      {:ok, _} = PartySystem.convert_raid(first)
      {:ok, _} = PartySystem.change_subgroup(first, second, 1)
      on_exit(fn -> Enum.each(guids, &PartySystem.leave/1) end)

      Chat.handle(state(first, "First"), 1, 7, "subgroup", nil)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 1, message: "subgroup"}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 1, message: "subgroup"}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{}}}

      for type <- [2, 0x57, 0x58] do
        Chat.handle(state(first, "First"), type, 7, "raid", nil)

        for _ <- 1..3 do
          assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: ^type, message: "raid"}}}
        end
      end

      for type <- [0x57, 0x58], do: Chat.handle(state(second, "Second"), type, 7, "forged", nil)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{}}}
      {:ok, _} = PartySystem.set_assistant(first, second, true)
      Chat.handle(state(second, "Second"), 0x58, 7, "assistant", nil)

      for _ <- 1..3 do
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 0x58, message: "assistant"}}}
      end
    end

    test "does not turn unsupported audiences into global chat" do
      observer = unique_guid()
      {:ok, _owner} = EntityRegistry.register(observer)
      SpatialHash.insert(:players, observer, 0, 0, 0, 0)
      state = state(unique_guid(), "Guildless")

      assert Chat.handle(state, 0x03, 7, "not global", nil) == state
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "not global"}}}

      SpatialHash.remove(:players, observer)
      EntityRegistry.unregister(observer)
    end

    test "rejects unlearned and forged speech before delivery" do
      state = state(unique_guid(), "Speaker")
      assert Chat.handle(state, 0, 6, "unlearned", nil) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgNotification{message: message}}}
      assert message == "You have not learned that language."

      for language <- [0, 99, 0xFFFFFFFF] do
        assert Chat.handle(state, 0, language, "forged", nil) == state
      end

      refute_receive {:"$gen_cast", {:send_packet, _packet}}
    end

    test "broadcasts aura-modified speech and keeps whispers readable" do
      sender = state(unique_guid(), "Speaker")
      receiver = state(unique_guid(), "Listener")

      for character <- [sender.character, receiver.character] do
        EntityRegistry.register(character.object.guid)
        Presence.enter(character, %{name: character.internal.name})
        on_exit(fn -> Presence.leave(character) end)
      end

      holder = %Holder{spell: %Spell{id: 1714}, auras: [%AuraData{type: :mod_language, misc_value: 8}]}
      character = %{sender.character | unit: %{sender.character.unit | auras: [holder]}}
      sender = %{sender | character: character}

      Chat.handle(sender, 0, 7, "cursed speech", nil)

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{chat_type: 0, language: 8, message: "cursed speech"}}}

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{chat_type: 0, language: 8, message: "cursed speech"},
                       [source_guid: source_guid]}}

      assert source_guid == sender.guid

      Chat.handle(sender, 6, 7, "private speech", "Listener")
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 6, language: 0}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 7, language: 0}}}
    end

    test "keeps addon payloads intact without interpreting commands" do
      first = unique_guid()
      second = unique_guid()
      EntityRegistry.register(first)
      EntityRegistry.register(second)
      :ok = PartySystem.invite(first, "First", second)
      {:ok, _group} = PartySystem.accept(second, "Second")
      on_exit(fn -> PartySystem.leave(first) end)
      state = state(first, "First")

      assert Chat.handle(state, 1, 0xFFFFFFFF, ".die", nil) == state

      for _ <- 1..2 do
        assert_receive {:"$gen_cast",
                        {:send_packet, %Message.SmsgMessagechat{chat_type: 1, language: 0xFFFFFFFF, message: ".die"}}}
      end
    end
  end

  defp state(guid, name) do
    %{
      guid: guid,
      ready: true,
      character: %Character{
        object: %Object{guid: guid},
        player: %Player{flags: 0},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        unit: %Unit{race: 1, health: 100, max_health: 100, auras: []},
        internal: %Internal{
          name: name,
          spellbook: %{668 => %Spell{id: 668, effects: [%Effect{type: :language, misc_value: 7}]}}
        }
      }
    }
  end

  defp unique_guid, do: System.unique_integer([:positive, :monotonic])
end
