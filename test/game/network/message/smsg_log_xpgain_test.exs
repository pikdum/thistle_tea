defmodule ThistleTea.Game.Network.Message.SmsgLogXpgainTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgLogXpgain

  describe "to_binary/1" do
    test "serializes kill XP gain with raw XP and group bonus" do
      binary =
        SmsgLogXpgain.to_binary(%SmsgLogXpgain{
          target: 0xAABB,
          total_exp: 50,
          experience_without_rested: 50,
          exp_group_bonus: 1.0
        })

      assert binary ==
               <<0xAABB::little-size(64), 50::little-size(32), 0::little-size(8), 50::little-size(32),
                 1.0::little-float-size(32)>>
    end

    test "serializes non-kill XP gain without trailing fields" do
      binary = SmsgLogXpgain.to_binary(%SmsgLogXpgain{target: 0xAABB, total_exp: 50, exp_type: :non_kill})

      assert binary == <<0xAABB::little-size(64), 50::little-size(32), 1::little-size(8)>>
    end
  end
end
