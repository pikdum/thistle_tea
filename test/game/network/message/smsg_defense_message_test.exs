defmodule ThistleTea.Game.Network.Message.SmsgDefenseMessageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgDefenseMessage

  describe "to_binary/1" do
    test "encodes the build-5875 opcode and terminated byte length" do
      assert SmsgDefenseMessage.opcode() == 0x33B

      assert SmsgDefenseMessage.to_binary(%SmsgDefenseMessage{zone_id: 139, text: "Tower captured!"}) ==
               <<139::little-size(32), 16::little-size(32), "Tower captured!", 0>>
    end
  end
end
