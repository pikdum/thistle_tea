defmodule ThistleTea.Game.Network.Message.MsgMoveTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Message.MsgMove
  alias ThistleTea.Game.Network.Session

  describe "handle/2" do
    test "routes movement to the active controlled unit without moving the character" do
      mover_guid = :erlang.unique_integer([:positive])
      {:ok, _owner} = Entity.register(mover_guid)

      session = %Session{
        guid: 23,
        active_mover_guid: mover_guid,
        ready: true,
        character: %Character{unit: %Unit{charm: mover_guid}}
      }

      message = %MsgMove{opcode: :MSG_MOVE_HEARTBEAT, payload: <<1, 2, 3>>}

      assert MsgMove.handle(message, session) == session
      assert_receive {:controlled_move, <<1, 2, 3>>, :MSG_MOVE_HEARTBEAT}
    end

    test "rejects a mover that is not the character's charm" do
      mover_guid = :erlang.unique_integer([:positive])
      {:ok, _owner} = Entity.register(mover_guid)

      session = %Session{
        guid: 23,
        active_mover_guid: mover_guid,
        ready: true,
        character: %Character{unit: %Unit{charm: mover_guid + 1}}
      }

      message = %MsgMove{opcode: :MSG_MOVE_HEARTBEAT, payload: <<1, 2, 3>>}

      assert MsgMove.handle(message, session) == session
      refute_receive {:controlled_move, _, _}
    end
  end
end
