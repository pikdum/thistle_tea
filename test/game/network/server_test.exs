defmodule ThistleTea.Game.Network.ServerTest do
  use ExUnit.Case, async: true
  use ThistleTea.Game.Network.Opcodes, [:SMSG_UPDATE_OBJECT]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.Server
  alias ThistleTea.Game.Network.UpdateBatcher
  alias ThistleTea.Game.Network.UpdateObject

  describe "UpdateBatcher.batch/2" do
    test "drains pending update structs into a single packet" do
      player_update = update_object(:player, 1)
      mob_update = update_object(:unit, 2)
      next_player_update = update_object(:player, 3)

      send(self(), {:"$gen_cast", {:send_packet, mob_update}})
      send(self(), {:"$gen_cast", {:send_packet, next_player_update}})

      {packet, updates} = UpdateBatcher.batch(player_update, nil)

      assert object_count(packet) == 3
      assert length(updates) == 3
    end

    test "only drains UpdateObject casts; leaves other messages in the mailbox" do
      send(self(), {:"$gen_cast", {:send_packet, %Packet{opcode: 0x123, payload: <<>>}}})

      {packet, _updates} = UpdateBatcher.batch(update_object(:player, 1), nil)
      assert object_count(packet) == 1

      assert_received {:"$gen_cast", {:send_packet, %Packet{opcode: 0x123}}}
    end

    test "dedupes values blocks for the same guid keeping the newest" do
      stale = update_object(:player, 1, :values)
      fresh = update_object(:player, 1, :values)

      send(self(), {:"$gen_cast", {:send_packet, fresh}})

      {packet, updates} = UpdateBatcher.batch(stale, nil)

      assert object_count(packet) == 1
      assert [%UpdateObject{update_type: :values}] = updates
    end
  end

  describe "handle_cast/2" do
    test "drops source-scoped packets for untracked entities" do
      socket = %{read_timeout: 0}
      state = %{tracked_entities: MapSet.new()}
      packet = %Packet{opcode: 0x123, payload: <<>>}

      assert {:noreply, {^socket, ^state}, 0} =
               Server.handle_cast({:send_packet, packet, source_guid: 1}, {socket, state})
    end

    test "drops destroy packets for untracked entities" do
      socket = %{read_timeout: 0}
      state = %{tracked_entities: MapSet.new()}
      packet = %Message.SmsgDestroyObject{guid: 1}

      assert {:noreply, {^socket, ^state}, 0} = Server.handle_cast({:send_packet, packet}, {socket, state})
    end

    test "raises when a serialized update object packet reaches the server" do
      socket = %{read_timeout: 0}
      state = %{}
      packet = %Packet{opcode: @smsg_update_object, payload: <<>>}

      assert_raise RuntimeError, "SMSG_UPDATE_OBJECT packets must be sent as UpdateObject structs", fn ->
        Server.handle_cast({:send_packet, packet}, {socket, state})
      end
    end

    test "marks player in combat when a mob attack lands" do
      socket = %{read_timeout: 0}
      sitting = %{character(1, health: 80, max_health: 100, stand_state: 1) | player: %Player{}}
      state = %{character: sitting}

      assert {:noreply, {^socket, %{character: character}}, {:continue, :maybe_broadcast_update}} =
               Server.handle_cast({:receive_attack, %{caster: 2, damage: 10}}, {socket, state})

      assert character.unit.health == 60
      assert character.internal.in_combat == true
      assert is_integer(character.internal.last_hostile_time)
      assert Regen.tick(character, 1_000).unit.health == 60
    end
  end

  describe "Network.send_packet/3" do
    test "includes source guid metadata in casts" do
      packet = %Packet{opcode: 0x123, payload: <<>>}

      assert :ok = Network.send_packet(packet, self(), source_guid: 1)

      assert_receive {:"$gen_cast", {:send_packet, ^packet, [source_guid: 1]}}
    end
  end

  defp update_object(:player, guid) do
    update_object(:player, guid, :create_object2)
  end

  defp update_object(:unit, guid) do
    update_object(:unit, guid, :create_object2)
  end

  defp update_object(:player, guid, update_type) do
    %UpdateObject{
      update_type: update_type,
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

  defp update_object(:unit, guid, update_type) do
    %UpdateObject{
      update_type: update_type,
      object_type: :unit,
      movement_block: %MovementBlock{update_flag: 0, position: {0.0, 0.0, 0.0, 0.0}},
      object: object(guid),
      unit: unit()
    }
  end

  defp character(guid, unit_attrs) do
    %Character{
      object: object(guid),
      unit: struct(unit(), unit_attrs),
      internal: %Internal{map: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
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
      max_power1: 100,
      power_type: 0,
      level: 10,
      race: 1,
      class: 1,
      gender: 1,
      spirit: 50
    }
  end

  defp object_count(%Packet{payload: <<count::little-size(32), 0, _body::binary>>}), do: count
end
