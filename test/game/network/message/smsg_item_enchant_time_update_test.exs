defmodule ThistleTea.Game.Network.Message.SmsgItemEnchantTimeUpdateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgItemEnchantTimeUpdate

  test "encodes the item enchant timer" do
    message = %SmsgItemEnchantTimeUpdate{
      item_guid: 0x4000_0000_0000_002A,
      slot: 1,
      duration_seconds: 600,
      player_guid: 0x0000_0000_0000_0063
    }

    assert SmsgItemEnchantTimeUpdate.to_binary(message) ==
             <<0x4000_0000_0000_002A::little-size(64), 1::little-size(32), 600::little-size(32), 0x63::little-size(64)>>
  end
end
