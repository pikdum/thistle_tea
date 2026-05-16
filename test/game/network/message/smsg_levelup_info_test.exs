defmodule ThistleTea.Game.Network.Message.SmsgLevelupInfoTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgLevelupInfo

  describe "to_binary/1" do
    test "serializes vanilla level-up info" do
      binary =
        SmsgLevelupInfo.to_binary(%SmsgLevelupInfo{
          new_level: 2,
          health: 19,
          mana: 0,
          strength: 1,
          agility: 1,
          stamina: 1
        })

      assert byte_size(binary) == 48

      assert binary ==
               <<2::little-size(32), 19::little-size(32), 0::little-size(32), 0::little-size(32), 0::little-size(32),
                 0::little-size(32), 0::little-size(32), 1::little-size(32), 1::little-size(32), 1::little-size(32),
                 0::little-size(32), 0::little-size(32)>>
    end
  end
end
