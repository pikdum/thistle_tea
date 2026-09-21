defmodule ThistleTea.Game.ChatTest do
  use ExUnit.Case, async: false

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
      Chat.handle(state, 6, 0, "Hello", "Absent#{unique_guid()}")
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
      assert Chat.handle(state, 0x01, 0, "party only", nil) == state

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 0x01, message: "party only"}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{chat_type: 0x01, message: "party only"}}}

      {:ok, _outcome} = PartySystem.leave(first)
      EntityRegistry.unregister(first)
      EntityRegistry.unregister(second)
    end

    test "does not turn unsupported audiences into global chat" do
      observer = unique_guid()
      {:ok, _owner} = EntityRegistry.register(observer)
      SpatialHash.insert(:players, observer, 0, 0, 0, 0)
      state = state(unique_guid(), "Guildless")

      assert Chat.handle(state, 0x03, 0, "not global", nil) == state
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "not global"}}}

      SpatialHash.remove(:players, observer)
      EntityRegistry.unregister(observer)
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
        unit: %Unit{race: 1},
        internal: %Internal{name: name}
      }
    }
  end

  defp unique_guid, do: System.unique_integer([:positive, :monotonic])
end
