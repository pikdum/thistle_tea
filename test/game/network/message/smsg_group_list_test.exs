defmodule ThistleTea.Game.Network.Message.SmsgGroupListTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgGroupList

  describe "to_binary/1" do
    test "includes the vanilla 1.12 dungeon difficulty byte for a group" do
      message = %SmsgGroupList{
        members: [%{name: "Member", guid: 2, online?: true, flags: 0}],
        leader: 1,
        loot_method: 3,
        loot_threshold: 2,
        dungeon_difficulty: 0
      }

      assert SmsgGroupList.to_binary(message) ==
               <<0, 0, 1::little-size(32), "Member", 0, 2::little-size(64), 1, 0, 1::little-size(64), 3,
                 0::little-size(64), 2, 0>>
    end

    test "ends after the leader guid when clearing a group" do
      assert SmsgGroupList.to_binary(%SmsgGroupList{}) == <<0, 0, 0::little-size(32), 0::little-size(64)>>
    end
  end
end
