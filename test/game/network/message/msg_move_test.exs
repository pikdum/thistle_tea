defmodule ThistleTea.Game.Network.Message.MsgMoveTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Taxi.Flight
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.MsgMove

  describe "handle/2" do
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
  end

  defp controlled_character(guid) do
    %Character{unit: %Unit{}, internal: %Internal{}}
    |> Companion.activate(:possession, %EntityRef{guid: guid, entry: 1, spell_id: 126})
  end
end
