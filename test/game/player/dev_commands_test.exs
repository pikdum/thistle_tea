defmodule ThistleTea.Game.Player.DevCommandsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.PostOffice

  describe ".mail" do
    test "posts an immediate letter to an offline character" do
      id = System.unique_integer([:positive, :monotonic])
      name = "Mailtest#{id}"
      recipient_guid = Guid.from_low_guid(:player, id)

      recipient = %Character{
        id: id,
        account_id: id,
        object: %Object{guid: recipient_guid},
        internal: %Internal{name: name}
      }

      CharacterStore.put(recipient)
      on_exit(fn -> :ets.delete(CharacterStore, id) end)

      sender_guid = Guid.from_low_guid(:player, id + 1)
      state = %{guid: sender_guid}

      assert {:handled, ^state} = DevCommands.run(state, ".mail #{name} hello from a debug command")
      assert {token, [mail]} = PostOffice.open(recipient_guid)

      assert mail.sender == sender_guid
      assert mail.receiver == recipient_guid
      assert mail.subject == "Debug mail"
      assert mail.body == "hello from a debug command"
      assert mail.deliver_at <= System.monotonic_time(:millisecond)

      PostOffice.acknowledge(recipient_guid, token, [mail.id])
      assert :ok = PostOffice.close(recipient_guid, token, [])
    end

    test "rejects a missing message" do
      state = %{guid: Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))}

      assert {:handled, ^state} = DevCommands.run(state, ".mail Nobody")
    end
  end
end
