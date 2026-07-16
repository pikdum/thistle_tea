defmodule ThistleTea.Game.Network.Message.SmsgUpdateLastInstanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgUpdateLastInstance

  describe "to_binary/1" do
    test "encodes the map" do
      assert SmsgUpdateLastInstance.to_binary(%SmsgUpdateLastInstance{map: 389}) == <<389::little-size(32)>>
    end
  end
end
