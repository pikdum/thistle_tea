defmodule ThistleTea.Game.Network.Message.SmsgSpellheallogTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgSpellheallog

  describe "to_binary/1" do
    test "encodes vanilla packed GUIDs and a one-byte critical flag" do
      for {critical?, flag} <- [{false, 0}, {true, 1}] do
        message = %SmsgSpellheallog{target: 0x0102, caster: 0x030004, spell_id: 2050, amount: 25, critical?: critical?}

        assert SmsgSpellheallog.to_binary(message) ==
                 <<3, 2, 1, 5, 4, 3, 2050::little-size(32), 25::little-size(32), flag>>
      end
    end
  end
end
