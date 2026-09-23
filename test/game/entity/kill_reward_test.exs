defmodule ThistleTea.Game.Entity.KillRewardTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.KillReward
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Member

  describe "selection/3" do
    test "keeps the original group after its tagger joins another group" do
      old_group = %Group{id: 10, members: [%Member{guid: 2}]}
      new_group = %Group{id: 20, members: [%Member{guid: 1}]}
      mob = %Mob{internal: %Internal{loot: %Loot{tapped_by: %Tap{player: 1, group_id: 10}}}}
      opts = [group: fn 10 -> old_group end, group_of: fn 1 -> new_group end]
      assert KillReward.selection(mob, 3, opts) == {:group, old_group}

      opts = Keyword.put(opts, :group, fn _id -> nil end)
      assert KillReward.selection(mob, 3, opts) == {:group, new_group}
      opts = Keyword.put(opts, :group_of, fn _guid -> nil end)
      assert KillReward.selection(mob, 3, opts) == {:solo, 1}
    end

    test "resolves pet killing blows when the creature was not tagged" do
      pet = Guid.from_low_guid(:pet, 1, 1)
      mob = %Mob{internal: %Internal{}}
      opts = [group: fn _id -> nil end, group_of: fn _guid -> nil end, metadata: fn ^pet -> %{owner_guid: 7} end]
      assert KillReward.selection(mob, pet, opts) == {:solo, 7}
      assert KillReward.selection(mob, nil, opts) == nil
      assert KillReward.selection(mob, pet, Keyword.put(opts, :metadata, fn _guid -> nil end)) == nil
    end
  end

  describe "controlling_player/2" do
    test "credits a possessed player's controller until control ends" do
      assert KillReward.controlling_player(1, fn 1 -> %{owner_guid: 2} end) == 2
      assert KillReward.controlling_player(1, fn 1 -> %{owner_guid: nil} end) == 1
      assert KillReward.controlling_player(1, fn 1 -> nil end) == 1
    end
  end

  describe "eligible_members/3" do
    test "requires a living nearby member of the selected group" do
      mob = %Mob{}
      group = %Group{id: 10, members: Enum.map(1..4, &%Member{guid: &1})}

      opts = [
        nearby: fn ^mob, 74.0 -> [{1, 0}, {2, 73}, {3, 74}, {5, 1}] end,
        metadata: fn guid -> %{level: 60, alive?: guid != 2} end
      ]

      assert KillReward.eligible_members(mob, group, opts) == [%{guid: 1, level: 60}, %{guid: 3, level: 60}]
    end
  end
end
