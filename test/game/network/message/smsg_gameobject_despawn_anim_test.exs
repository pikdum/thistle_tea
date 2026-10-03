defmodule ThistleTea.Game.Network.Message.SmsgGameobjectDespawnAnimTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgGameobjectDespawnAnim

  describe "to_binary/1" do
    test "encodes the build-5875 opcode and object guid" do
      assert SmsgGameobjectDespawnAnim.opcode() == 0x215

      assert SmsgGameobjectDespawnAnim.to_binary(%SmsgGameobjectDespawnAnim{guid: 0xF110_0000_0000_002A}) ==
               <<0xF110_0000_0000_002A::little-size(64)>>
    end
  end
end
