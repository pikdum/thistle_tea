defmodule ThistleTea.Game.Network.Message.MovementSpeedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Packet

  @modes [
    {:run_speed, Message.SmsgForceRunSpeedChange, Message.CmsgForceRunSpeedChangeAck, 0xE3},
    {:run_back_speed, Message.SmsgForceRunBackSpeedChange, Message.CmsgForceRunBackSpeedChangeAck, 0xE5},
    {:swim_speed, Message.SmsgForceSwimSpeedChange, Message.CmsgForceSwimSpeedChangeAck, 0xE7},
    {:swim_back_speed, Message.SmsgForceSwimBackSpeedChange, Message.CmsgForceSwimBackSpeedChangeAck, 0x2DD}
  ]

  describe "to_binary/1" do
    test "observer packets include movement information before the speed" do
      movement = %MovementBlock{position: {1.0, 2.0, 3.0, 0.5}, movement_flags: 0, timestamp: 100}

      info =
        <<0::little-size(32), 100::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 0::little-size(32)>>

      for {module, opcode} <- [
            {Message.MsgMoveSetRunSpeed, 0xCD},
            {Message.MsgMoveSetRunBackSpeed, 0xCF},
            {Message.MsgMoveSetSwimSpeed, 0xD3},
            {Message.MsgMoveSetSwimBackSpeed, 0xD5}
          ] do
        packet = module.to_packet(struct!(module, guid: 42, movement_block: movement, speed: 3.25))
        assert packet.opcode == opcode
        assert packet.payload == <<1, 42, info::binary, 3.25::little-float-size(32)>>
      end
    end

    test "encodes packed GUID, movement counter and speed for every mode" do
      for {_type, server, _client, _opcode} <- @modes do
        packet = struct!(server, guid: 42, move_event: 9, speed: 3.25)
        assert server.to_binary(packet) == <<1, 42, 9::little-size(32), 3.25::little-float-size(32)>>
      end
    end
  end

  describe "from_binary/1" do
    test "dispatches vanilla acknowledgements for every mode" do
      for {_type, _server, client, opcode} <- @modes do
        payload = <<42::little-size(64), 9::little-size(32), 0::size(224), 3.25::little-float-size(32)>>

        assert Dispatch.to_message(Packet.build(payload, opcode)) ==
                 struct!(client, guid: 42, counter: 9, new_speed: 3.25)
      end
    end
  end

  describe "emit/3" do
    test "delivers each movement mode to the explicit owner" do
      character = %Character{object: %Object{guid: 42}}

      for {type, server, _client, _opcode} <- @modes do
        effect = Effects.movement_speed_changed(3.25, type)
        assert EventSink.emit(character, effect, Context.new(self())) == character
        assert_receive {:"$gen_cast", {:send_packet, packet}}
        assert packet == struct!(server, guid: 42, speed: 3.25)
      end
    end
  end

  describe "handle/2" do
    test "settles a shared sequence without changing authoritative speeds" do
      character = %Character{movement_block: struct!(MovementBlock, MovementBlock.player_speeds())}
      state = %State{guid: 42, character: character}

      state =
        Enum.reduce(@modes, state, fn {_type, server, _client, _opcode}, state ->
          {_packet, state} = MovementControl.prepare(struct!(server, guid: 42, speed: 3.25), state)
          state
        end)

      assert state.movement_counter == 4
      assert map_size(state.pending_movement_acks) == 4

      state =
        @modes
        |> Enum.with_index()
        |> Enum.reverse()
        |> Enum.reduce(state, fn {{_type, _server, client, _opcode}, counter}, state ->
          state = client.handle(struct!(client, guid: 42, counter: counter, new_speed: 3.25), state)
          assert state.character == character
          state
        end)

      assert state.pending_movement_acks == %{}
    end

    test "rejects wrong owners, counters, modes and speeds" do
      for {type, _server, client, _opcode} <- @modes do
        state = %State{guid: 42, pending_movement_acks: %{7 => {type, 3.25}}}

        for {guid, counter, speed} <- [{41, 7, 3.25}, {42, 8, 3.25}, {42, 7, 7.0}] do
          assert client.handle(struct!(client, guid: guid, counter: counter, new_speed: speed), state) == state
        end

        wrong_mode = %{state | pending_movement_acks: %{7 => {:wrong_speed, 3.25}}}
        assert client.handle(struct!(client, guid: 42, counter: 7, new_speed: 3.25), wrong_mode) == wrong_mode
      end
    end

    test "accepts float precision differences and finishes pending spirit release" do
      state = %State{guid: 42, pending_movement_acks: %{7 => {:swim_speed, 4.722222}}}
      state = MovementControl.defer_repop(state, {10.0, 20.0, 30.0, 1})
      token = state.pending_repop.token
      assert_receive {:"$gen_cast", {:finish_repop, ^token}}
      message = %Message.CmsgForceSwimSpeedChangeAck{guid: 42, counter: 7, new_speed: 4.72222185}
      state = Message.CmsgForceSwimSpeedChangeAck.handle(message, state)
      assert state.pending_movement_acks == %{}
      assert state.pending_repop == nil
      assert_receive {:"$gen_cast", {:start_teleport, 10.0, 20.0, 30.0, 1}}
    end
  end
end
