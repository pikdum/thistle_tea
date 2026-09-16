defmodule ThistleTea.Game.Network.Message.SmsgCastResultTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgCastResult

  describe "to_binary/1" do
    test "encodes disarmed weapon failures without item-class payloads" do
      message = SmsgCastResult.failure(78, :equipped_item)
      assert SmsgCastResult.to_binary(message) == <<78::little-size(32), 2, 0x18>>
    end
  end
end
