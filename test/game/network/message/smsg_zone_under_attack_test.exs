defmodule ThistleTea.Game.Network.Message.SmsgZoneUnderAttackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgZoneUnderAttack

  describe "to_binary/1" do
    test "encodes the build-5875 opcode and area id" do
      assert SmsgZoneUnderAttack.opcode() == 0x254
      assert SmsgZoneUnderAttack.to_binary(%SmsgZoneUnderAttack{area_id: 87}) == <<87::little-size(32)>>
    end
  end
end
