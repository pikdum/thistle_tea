defmodule ThistleTea.Game.Network.Message.SmsgEnvironmentalDamageLogTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgEnvironmentalDamageLog

  describe "to_binary/1" do
    test "encodes fire with separate absorbed and resisted amounts" do
      message = %SmsgEnvironmentalDamageLog{guid: 1, damage_type: 5, damage: 20, absorb: 30, resist: 150}

      assert SmsgEnvironmentalDamageLog.to_binary(message) ==
               <<1::little-64, 5, 20::little-32, 30::little-32, 150::little-32>>
    end

    test "encodes the vanilla environmental damage packet" do
      message = %SmsgEnvironmentalDamageLog{guid: 0x0102030405060708, damage_type: 2, damage: 297}

      assert SmsgEnvironmentalDamageLog.opcode() == 0x1FC

      assert SmsgEnvironmentalDamageLog.to_binary(message) ==
               <<8, 7, 6, 5, 4, 3, 2, 1, 2, 41, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
    end
  end
end
