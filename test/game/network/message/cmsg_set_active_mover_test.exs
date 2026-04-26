defmodule ThistleTea.Game.Network.Message.CmsgSetActiveMoverTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgSetActiveMover

  describe "from_binary/1" do
    test "parses mover guid" do
      assert %CmsgSetActiveMover{guid: 23} = CmsgSetActiveMover.from_binary(<<23::little-size(64)>>)
    end
  end

  describe "handle/2" do
    test "marks matching player ready and requests object spawn" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 23}, %{guid: 23, ready: false})

      assert state.ready
      assert_receive :spawn_objects
    end

    test "ignores mismatched mover" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 24}, %{guid: 23, ready: false})

      refute state.ready
      refute_receive :spawn_objects
    end
  end
end
