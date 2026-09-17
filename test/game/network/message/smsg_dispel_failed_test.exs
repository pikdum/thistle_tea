defmodule ThistleTea.Game.Network.Message.SmsgDispelFailedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgDispelFailed

  describe "to_binary/1" do
    test "encodes full GUIDs followed by each failed spell without a count" do
      message = %SmsgDispelFailed{caster: 2, target: 0xF130000000000001, spells: [123, 123, 456]}

      assert SmsgDispelFailed.to_binary(message) ==
               <<2::little-size(64), 0xF130000000000001::little-size(64), 123::little-size(32), 123::little-size(32),
                 456::little-size(32)>>
    end
  end
end
