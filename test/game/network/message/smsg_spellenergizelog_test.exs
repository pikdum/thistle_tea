defmodule ThistleTea.Game.Network.Message.SmsgSpellenergizelogTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgSpellenergizelog

  describe "to_binary/1" do
    test "encodes packed target and caster followed by spell, power type, and amount" do
      message = %SmsgSpellenergizelog{target: 0x0304, caster: 0x0102, spell_id: 2687, power_type: 1, amount: 100}

      assert SmsgSpellenergizelog.to_binary(message) ==
               <<3, 4, 3, 3, 2, 1, 2687::little-size(32), 1::little-size(32), 100::little-size(32)>>
    end
  end
end
