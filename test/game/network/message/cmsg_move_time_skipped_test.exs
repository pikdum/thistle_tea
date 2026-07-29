defmodule ThistleTea.Game.Network.Message.CmsgMoveTimeSkippedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.CmsgMoveTimeSkipped
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.Visibility

  defmodule TransportUpdateServer do
    @moduledoc false
    use GenServer

    def start_link({guid, update}) do
      GenServer.start_link(__MODULE__, update, name: EntityRegistry.via(guid))
    end

    @impl GenServer
    def init(update), do: {:ok, update}

    @impl GenServer
    def handle_call(:transport_update, _from, update), do: {:reply, {:ok, update}, update}
  end

  describe "from_binary/1" do
    test "parses the mover and skipped milliseconds" do
      payload = <<23::little-size(64), 32::little-size(32)>>

      assert CmsgMoveTimeSkipped.from_binary(payload) == %CmsgMoveTimeSkipped{guid: 23, lag: 32}
    end
  end

  describe "handle/2" do
    test "recreates a newly boarded transport once" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      transport_guid = Guid.from_low_guid(:mo_transport, System.unique_integer([:positive]))

      transport_update = %UpdateObject{
        update_type: :create_object2,
        object: %Object{guid: transport_guid}
      }

      start_supervised!({TransportUpdateServer, {transport_guid, transport_update}})

      state = %State{
        guid: player_guid,
        transport_refresh_pending: transport_guid,
        character: %Character{
          movement_block: %MovementBlock{transport_guid: transport_guid, timestamp: 100}
        }
      }

      message = %CmsgMoveTimeSkipped{guid: player_guid, lag: 25}
      state = CmsgMoveTimeSkipped.handle(message, state)

      assert state.transport_refresh_pending == nil
      assert state.character.movement_block.timestamp == 125

      out_of_range = UpdateObject.out_of_range([transport_guid])
      assert_receive {:"$gen_cast", {:send_packet, ^out_of_range}}

      sink_state = %State{connection_pid: self(), tracked_entities: MapSet.new([transport_guid])}
      sink_state = PacketSink.send(sink_state, out_of_range)
      refute Visibility.tracked?(sink_state, transport_guid)
      assert_receive {:"$gen_cast", {:write_packet, %Packet{}}}

      assert_receive {:"$gen_cast",
                      {:send_packet, %UpdateObject{object: %Object{guid: ^transport_guid}, has_transport: false}}}

      assert CmsgMoveTimeSkipped.handle(message, state).transport_refresh_pending == nil
      refute_receive {:"$gen_cast", {:send_packet, %UpdateObject{update_type: :out_of_range_objects}}}
      refute_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: %Object{guid: ^transport_guid}}}}
    end

    test "ignores another mover" do
      state = %State{guid: 1, character: %Character{movement_block: %MovementBlock{timestamp: 100}}}

      assert CmsgMoveTimeSkipped.handle(%CmsgMoveTimeSkipped{guid: 2, lag: 25}, state) == state
    end

    test "broadcasts skipped time to other viewers" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      other_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      {:ok, _registration} = Entity.register(other_guid)
      on_exit(fn -> Entity.unregister(other_guid) end)

      state = %State{
        guid: player_guid,
        player_guids: [player_guid, other_guid],
        character: %Character{
          object: %Object{guid: player_guid},
          movement_block: %MovementBlock{timestamp: 100}
        }
      }

      state = CmsgMoveTimeSkipped.handle(%CmsgMoveTimeSkipped{guid: player_guid, lag: 25}, state)

      assert state.character.movement_block.timestamp == 125

      opcode = Opcodes.get(:MSG_MOVE_TIME_SKIPPED)
      payload = BinaryUtils.pack_guid(player_guid) <> <<25::little-size(32)>>

      assert_receive {:"$gen_cast",
                      {:send_packet, %Packet{opcode: ^opcode, payload: ^payload}, [source_guid: ^player_guid]}}
    end
  end

  describe "Dispatch.implemented?/1" do
    test "recognizes the time-skipped opcode" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_MOVE_TIME_SKIPPED))
    end
  end
end
