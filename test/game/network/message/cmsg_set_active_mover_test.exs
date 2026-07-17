defmodule ThistleTea.Game.Network.Message.CmsgSetActiveMoverTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Message.CmsgSetActiveMover
  alias ThistleTea.Game.Network.Session

  describe "from_binary/1" do
    test "parses mover guid" do
      assert %CmsgSetActiveMover{guid: 23} = CmsgSetActiveMover.from_binary(<<23::little-size(64)>>)
    end
  end

  describe "handle/2" do
    test "marks matching player ready" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 23}, %Session{guid: 23})

      assert state.ready
      assert state.active_mover_guid == 23
      refute_receive :spawn_objects
    end

    test "ignores mismatched mover" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 24}, %Session{guid: 23})

      refute state.ready
      assert state.active_mover_guid == nil
      refute_receive :spawn_objects
    end

    test "accepts the character's controlled unit after entering the world" do
      session = %Session{guid: 23, ready: true, character: %Character{unit: %Unit{charm: 24}}}

      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 24}, session)

      assert state.active_mover_guid == 24
    end
  end
end
