defmodule ThistleTea.Game.Network.Message.SmsgClearCooldownTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgClearCooldown

  test "encodes the spell and target GUID" do
    message = %SmsgClearCooldown{spell_id: 23_989, target_guid: 0x0102030405060708}

    assert SmsgClearCooldown.to_binary(message) ==
             <<23_989::little-size(32), 0x0102030405060708::little-size(64)>>
  end
end
