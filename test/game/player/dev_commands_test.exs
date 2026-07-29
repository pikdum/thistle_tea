defmodule ThistleTea.Game.Player.DevCommandsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Entity.Server.Transport, as: TransportServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.WorldRef

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

  describe ".debug transport" do
    test "shows and advances the attached transport" do
      entry = System.unique_integer([:positive, :monotonic])
      route = TransportLogic.build_ship(entry, "Debug Ship", 10, ship_nodes(), 10, 1, 20_000)
      entity = GameObject.build_transport(transport_template(entry), TransportLogic.pose_at(route, 0))
      {:ok, pid} = TransportServer.start_link({entity, route, schedule: false, clock: fn -> 1_000 end})
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      player_guid = Guid.from_low_guid(:player, entry)

      character = %Character{
        object: %Object{guid: player_guid},
        movement_block: %MovementBlock{
          position: {-10.0, 0.0, 0.0, 0.0},
          transport_guid: entity.object.guid
        },
        internal: %Internal{world: WorldRef.open(0)}
      }

      state = %{guid: player_guid, character: character}

      assert {:handled, ^state} = DevCommands.run(state, ".debug transport")

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: status_message}}}

      assert status_message =~ "Debug Ship entry #{entry}"
      assert status_message =~ "0ms/20000ms"

      assert {:handled, ^state} = DevCommands.run(state, ".debug transport advance 3 #{entry}")

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Advanced transport " <> advance_message}}}

      assert advance_message == "#{entry} by 3s."

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: advanced_status}}}

      assert advanced_status =~ "3000ms/20000ms"
      assert Transports.get(entity.object.guid).progress_ms == 3_000
    end

    test "reports invalid schedule advancement" do
      state = %{guid: 1, character: debug_character()}

      assert {:handled, ^state} = DevCommands.run(state, ".debug transport advance tomorrow")

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: message}}}

      assert message =~ "Invalid command"
    end
  end

  defp debug_character do
    %Character{
      object: %Object{guid: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end

  defp transport_template(entry) do
    %GameObjectTemplate{
      entry: entry,
      type: 15,
      display_id: 3015,
      name: "Debug Ship",
      size: 1.0,
      flags: 0,
      faction: 0,
      data: [10, 10, 1] ++ List.duplicate(0, 21)
    }
  end

  defp ship_nodes do
    [
      transport_node(0, {-10.0, 0.0, 0.0}, 0, 0),
      transport_node(1, {0.0, 0.0, 0.0}, 2, 2),
      transport_node(2, {10.0, 0.0, 0.0}, 0, 0),
      transport_node(3, {20.0, 0.0, 0.0}, 2, 2),
      transport_node(4, {10.0, 0.0, 0.0}, 0, 0),
      transport_node(5, {0.0, 0.0, 0.0}, 2, 2)
    ]
  end

  defp transport_node(index, position, flags, delay) do
    %{node_index: index, map_id: 0, position: position, flags: flags, delay: delay}
  end
end
