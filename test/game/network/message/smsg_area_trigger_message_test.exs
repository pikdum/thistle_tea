defmodule ThistleTea.Game.Network.Message.SmsgAreaTriggerMessageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgAreaTriggerMessage

  describe "to_binary/1" do
    test "encodes a sized null-terminated message" do
      assert SmsgAreaTriggerMessage.to_binary(%SmsgAreaTriggerMessage{message: "Level 8 required"}) ==
               <<17::little-size(32), "Level 8 required", 0>>
    end
  end
end
