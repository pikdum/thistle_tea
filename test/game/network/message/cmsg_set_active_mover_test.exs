defmodule ThistleTea.Game.Network.Message.CmsgSetActiveMoverTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.CmsgSetActiveMover

  describe "from_binary/1" do
    test "parses mover guid" do
      assert %CmsgSetActiveMover{guid: 23} = CmsgSetActiveMover.from_binary(<<23::little-size(64)>>)
    end
  end

  describe "handle/2" do
    test "marks matching player ready" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 23}, %State{guid: 23})

      assert state.ready
      assert state.active_mover_guid == 23
      refute_receive :spawn_objects
    end

    test "ignores mismatched mover" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 24}, %State{guid: 23})

      refute state.ready
      assert state.active_mover_guid == nil
      refute_receive :spawn_objects
    end

    test "accepts the character's controlled unit after entering the world" do
      character =
        %Character{unit: %Unit{}, internal: %Internal{}}
        |> Companion.activate(:possession, %EntityRef{guid: 24, entry: 1, spell_id: 126})

      session = %State{guid: 23, ready: true, character: character}

      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 24}, session)

      assert state.active_mover_guid == 24
    end
  end
end
