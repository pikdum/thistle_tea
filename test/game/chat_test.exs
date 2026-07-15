defmodule ThistleTea.Game.ChatTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Chat
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  describe "handle/5" do
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
      character: %Character{
        unit: %Unit{race: 1},
        internal: %Internal{name: name}
      }
    }
  end

  defp unique_guid, do: System.unique_integer([:positive, :monotonic])
end
