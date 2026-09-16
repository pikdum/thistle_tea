defmodule ThistleTea.Game.Network.Message.MsgMoveTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Taxi.Flight
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Server.Player.ServerMovement
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.MsgMove
  alias ThistleTea.Game.Network.Message.SmsgEnvironmentalDamageLog
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.ClientMotion
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.WorldRef

  describe "handle/2" do
    test "landing damages the owner, projects health, and broadcasts the combat log once" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      {:ok, _owner} = Entity.register(guid)
      character = moving_character(guid)

      character = %{
        character
        | unit: %{character.unit | health: 1000, max_health: 1000, level: 10},
          player: %Player{flags: 0}
      }

      on_exit(fn -> Presence.leave(character) end)

      state = %State{
        guid: guid,
        packed_guid: BinaryUtils.pack_guid(guid),
        ready: true,
        character: character,
        next_exploration_check_at: Time.now() + 60_000,
        player_guids: []
      }

      falling = MsgMove.handle(move_message(:MSG_MOVE_HEARTBEAT, 0x4000, {0.0, 0.0, 30.0, 0.0}), state)
      landing = move_message(:MSG_MOVE_FALL_LAND, 0, {0.0, 0.0, 0.0, 0.0}, 2000)
      landed = MsgMove.handle(landing, falling)

      assert landed.character.unit.health == 703
      assert landed.character.internal.fall == nil
      refute landed.character.internal.broadcast_update?
      assert landed.character.internal.events == []

      assert_receive {:"$gen_cast",
                      {:send_packet, %SmsgEnvironmentalDamageLog{guid: ^guid, damage_type: 2, damage: 297}}}

      assert MsgMove.handle(landing, landed).character.unit.health == 703
      refute_receive {:"$gen_cast", {:send_packet, %SmsgEnvironmentalDamageLog{}}}
    end

    test "routes movement to the active controlled unit without moving the character" do
      mover_guid = :erlang.unique_integer([:positive])
      {:ok, _owner} = Entity.register(mover_guid)

      session = %State{
        guid: 23,
        active_mover_guid: mover_guid,
        ready: true,
        character: controlled_character(mover_guid)
      }

      message = %MsgMove{opcode: :MSG_MOVE_HEARTBEAT, payload: <<1, 2, 3>>}

      assert MsgMove.handle(message, session) == session
      assert_receive {:controlled_move, <<1, 2, 3>>, :MSG_MOVE_HEARTBEAT}
    end

    test "rejects a mover that is not the character's charm" do
      mover_guid = :erlang.unique_integer([:positive])
      {:ok, _owner} = Entity.register(mover_guid)

      session = %State{
        guid: 23,
        active_mover_guid: mover_guid,
        ready: true,
        character: controlled_character(mover_guid + 1)
      }

      message = %MsgMove{opcode: :MSG_MOVE_HEARTBEAT, payload: <<1, 2, 3>>}

      assert MsgMove.handle(message, session) == session
      refute_receive {:controlled_move, _, _}
    end

    test "ignores client movement during a taxi flight" do
      character = %Character{unit: %Unit{}, internal: %Internal{taxi_flight: struct(Flight)}}
      session = %State{guid: 23, ready: true, character: character}

      assert MsgMove.handle(%MsgMove{opcode: :MSG_MOVE_HEARTBEAT, payload: <<>>}, session) == session
    end

    test "ignores client movement during finite server movement" do
      session = %State{
        server_movement: %ServerMovement{token: make_ref(), timer_ref: make_ref()},
        character: %Character{}
      }

      assert MsgMove.handle(%MsgMove{opcode: :MSG_MOVE_HEARTBEAT, payload: <<>>}, session) == session
    end

    test "publishes forward motion immediately and clears it on stop" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      character = moving_character(guid)
      on_exit(fn -> Presence.leave(character) end)

      state = %State{
        guid: guid,
        packed_guid: BinaryUtils.pack_guid(guid),
        ready: true,
        character: character,
        player_guids: []
      }

      moving = MsgMove.handle(move_message(:MSG_MOVE_START_FORWARD, 0x00000001, {0.0, 0.0, 0.0, 0.0}), state)

      assert %ClientMotion{started_at: started_at, expires_at: expires_at, velocity: velocity} =
               Position.projection(guid)

      assert velocity == {70.0, 0.0, 0.0}
      assert expires_at == started_at + 750
      assert World.position(guid, started_at + 100) == {WorldRef.open(0), 7.0, 0.0, 0.0}

      assert Metadata.query(guid, [:movement_velocity, :moving_until]) == %{
               movement_velocity: {70.0, 0.0, 0.0},
               moving_until: expires_at
             }

      stopped = MsgMove.handle(move_message(:MSG_MOVE_STOP, 0, {35.0, 0.0, 0.0, 0.0}), moving)

      assert stopped.character.movement_block.position == {35.0, 0.0, 0.0, 0.0}
      assert Position.projection(guid) == nil
      assert World.position(guid) == {WorldRef.open(0), 35.0, 0.0, 0.0}
    end
  end

  defp move_message(opcode, flags, {x, y, z, orientation}, fall_time \\ 0) do
    payload =
      <<flags::little-size(32), 1_000::little-size(32), x::little-float-size(32), y::little-float-size(32),
        z::little-float-size(32), orientation::little-float-size(32), fall_time::little-size(32)>>

    %MsgMove{opcode: Opcodes.get(opcode), payload: payload}
  end

  defp moving_character(guid) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 0, auras: []},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{
        position: {0.0, 0.0, 0.0, 0.0},
        movement_flags: 0,
        walk_speed: 2.5,
        run_speed: 70.0,
        run_back_speed: 45.0,
        swim_speed: 47.0,
        swim_back_speed: 25.0
      }
    }
  end

  defp controlled_character(guid) do
    %Character{unit: %Unit{}, internal: %Internal{}}
    |> Companion.activate(:possession, %EntityRef{guid: guid, entry: 1, spell_id: 126})
  end
end
