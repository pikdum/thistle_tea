defmodule ThistleTea.Game.Network.ServerTest do
  use ExUnit.Case, async: true
  use ThistleTea.Game.Network.Opcodes, [:SMSG_UPDATE_OBJECT]

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.Server
  alias ThistleTea.Game.Network.UpdateObject

  describe "accumulate_updates/2" do
    test "drains pending update structs into a single packet" do
      player_update = update_object(:player, 1)
      mob_update = update_object(:unit, 2)
      next_player_update = update_object(:player, 3)

      send(self(), {:"$gen_cast", {:send_packet, mob_update}})
      send(self(), {:"$gen_cast", {:send_packet, next_player_update}})

      packet = Server.accumulate_updates(player_update, nil)

      assert object_count(packet) == 3
    end

    test "only drains UpdateObject casts; leaves other messages in the mailbox" do
      send(self(), {:"$gen_cast", {:send_packet, %Packet{opcode: 0x123, payload: <<>>}}})

      packet = Server.accumulate_updates(update_object(:player, 1), nil)
      assert object_count(packet) == 1

      assert_received {:"$gen_cast", {:send_packet, %Packet{opcode: 0x123}}}
    end
  end

  describe "handle_cast/2" do
    test "raises when a serialized update object packet reaches the server" do
      socket = %{read_timeout: 0}
      state = %{}
      packet = %Packet{opcode: @smsg_update_object, payload: <<>>}

      assert_raise RuntimeError, "SMSG_UPDATE_OBJECT packets must be sent as UpdateObject structs", fn ->
        Server.handle_cast({:send_packet, packet}, {socket, state})
      end
    end
  end

  defp update_object(:player, guid) do
    %UpdateObject{
      update_type: :create_object2,
      object_type: :player,
      movement_block: %MovementBlock{update_flag: 0, position: {0.0, 0.0, 0.0, 0.0}},
      object: object(guid),
      unit: unit(),
      player: %Player{
        gender: 1,
        skin: 1,
        face: 1,
        hair_style: 1,
        hair_color: 1,
        coinage: 500
      }
    }
  end

  defp update_object(:unit, guid) do
    %UpdateObject{
      update_type: :create_object2,
      object_type: :unit,
      movement_block: %MovementBlock{update_flag: 0, position: {0.0, 0.0, 0.0, 0.0}},
      object: object(guid),
      unit: unit()
    }
  end

  defp object(guid) do
    %Object{
      guid: guid,
      type: 1,
      entry: 1001,
      scale_x: 1.0
    }
  end

  defp unit do
    %Unit{
      health: 1000,
      power1: 100,
      power_type: 0,
      level: 10,
      race: 1,
      class: 1,
      gender: 1
    }
  end

  defp object_count(%Packet{payload: <<count::little-size(32), 0, _body::binary>>}), do: count
end
