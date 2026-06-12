defmodule ThistleTea.Game.Network.Message.CmsgSetActiveMoverTest do
  use ExUnit.Case, async: true

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
      refute_receive :spawn_objects
    end

    test "ignores mismatched mover" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 24}, %Session{guid: 23})

      refute state.ready
      refute_receive :spawn_objects
    end
  end
end
