defmodule ThistleTea.Game.Network.Message.SmsgSpelllogexecuteTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgSpelllogexecute

  describe "to_binary/1" do
    test "encodes durability item entries and all-items sentinels with unpacked target GUIDs" do
      message = %SmsgSpelllogexecute{
        caster: 0x0102,
        spell_id: 16_722,
        logs: [{:durability_damage, 0x0304, 18_194}, {:durability_damage, 0x0304, -1}]
      }

      assert SmsgSpelllogexecute.to_binary(message) ==
               <<3, 2, 1, 16_722::little-size(32), 2::little-size(32), 111::little-size(32), 1::little-size(32),
                 0x0304::little-size(64), 18_194::little-size(32), 0xFFFFFFFF::little-size(32), 111::little-size(32),
                 1::little-size(32), 0x0304::little-size(64), 0xFFFFFFFF::little-size(32), 0xFFFFFFFF::little-size(32)>>
    end

    test "encodes the packed caster and full target GUID used by build 5875" do
      message = %SmsgSpelllogexecute{caster: 0x0102, spell_id: 3391, logs: [{:extra_attacks, 0x0102, 2}]}

      assert SmsgSpelllogexecute.to_binary(message) ==
               <<3, 2, 1, 3391::little-size(32), 1::little-size(32), 19::little-size(32), 1::little-size(32),
                 0x0102::little-size(64), 2::little-size(32)>>
    end
  end
end
