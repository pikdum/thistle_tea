defmodule ThistleTea.Game.Network.Message.SmsgSummonRequestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgSummonRequest

  test "encodes the Vanilla summon request payload" do
    message = %SmsgSummonRequest{summoner_guid: 0x0102030405060708, zone_id: 12, auto_decline_ms: 120_000}

    assert SmsgSummonRequest.to_binary(message) ==
             <<0x0102030405060708::little-size(64), 12::little-size(32), 120_000::little-size(32)>>
  end
end
