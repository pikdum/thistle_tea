defmodule ThistleTea.Game.Network.Message.SmsgResurrectRequestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgResurrectRequest

  describe "to_binary/1" do
    test "encodes sickness and countdown controls independently" do
      assert SmsgResurrectRequest.to_binary(%SmsgResurrectRequest{guid: 9}) ==
               <<9::little-size(64), 1::little-size(32), 0, 0, 1>>

      packet = %SmsgResurrectRequest{guid: 9, name: "Healer", sickness?: true, delayed?: false}
      assert SmsgResurrectRequest.to_binary(packet) == <<9::little-size(64), 7::little-size(32), "Healer", 0, 1, 0>>
    end
  end
end
