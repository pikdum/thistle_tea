defmodule ThistleTea.Game.Network.Message.GossipPoiTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgGossipPoi

  describe "to_binary/1" do
    test "encodes the map flag before its null-terminated label" do
      packet = %SmsgGossipPoi{flags: 99, x: -8885.5, y: 640.25, icon: 6, data: 0, name: "Stormwind Bank"}

      assert SmsgGossipPoi.to_binary(packet) ==
               <<99::little-32, -8885.5::little-float-32, 640.25::little-float-32, 6::little-32, 0::little-32,
                 "Stormwind Bank", 0>>
    end
  end
end
