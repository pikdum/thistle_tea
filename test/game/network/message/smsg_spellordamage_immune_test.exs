defmodule ThistleTea.Game.Network.Message.SmsgSpellordamageImmuneTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgSpellordamageImmune

  describe "to_binary/1" do
    test "encodes full GUIDs and the vanilla log-format byte" do
      message = %SmsgSpellordamageImmune{caster: 0xF130000000000001, target: 2, spell_id: 772}

      assert SmsgSpellordamageImmune.to_binary(message) ==
               <<0xF130000000000001::little-size(64), 2::little-size(64), 772::little-size(32), 0>>
    end
  end
end
