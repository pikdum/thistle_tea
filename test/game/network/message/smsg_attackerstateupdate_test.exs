defmodule ThistleTea.Game.Network.Message.SmsgAttackerstateupdateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgAttackerstateupdate

  describe "to_binary/1" do
    test "encodes a school index and independent absorb and resist amounts" do
      message = %SmsgAttackerstateupdate{
        attacker: 1,
        target: 2,
        hit_info: 0x62,
        total_damage: 15,
        damages: [%{school: 2, damage_float: 15.0, damage_uint: 15, absorb: 10, resist: 75}]
      }

      assert SmsgAttackerstateupdate.to_binary(message) ==
               <<0x62::little-size(32), 1, 1, 1, 2, 15::little-size(32), 1, 2::little-size(32),
                 15.0::little-float-size(32), 15::little-size(32), 10::little-size(32), 75::little-size(32),
                 1::little-size(32), 0::little-size(32), 0::little-size(32), 0::little-size(32)>>
    end
  end
end
