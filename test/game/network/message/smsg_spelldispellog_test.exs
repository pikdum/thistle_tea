defmodule ThistleTea.Game.Network.Message.SmsgSpelldispellogTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgSpelldispellog

  describe "to_binary/1" do
    test "encodes packed victim and caster GUIDs and removed spells" do
      message = %SmsgSpelldispellog{victim: 0xF130000000000001, caster: 2, spells: [123, 456]}

      assert SmsgSpelldispellog.to_binary(message) ==
               <<0xC1, 1, 0x30, 0xF1, 1, 2, 2::little-size(32), 123::little-size(32), 456::little-size(32)>>
    end
  end
end
