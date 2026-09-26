defmodule ThistleTea.Game.Entity.KillRewardTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.DamageOrigin
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.KillReward
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.GroupReward.Award
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Member
  alias ThistleTea.Game.WorldRef

  setup [:reward_context]

  describe "selection/3" do
    test "keeps the original group after its tagger joins another group", %{mob: mob} do
      old_group = %Group{id: 10, members: [%Member{guid: 2}]}
      new_group = %Group{id: 20, members: [%Member{guid: 1}]}
      opts = [group: fn 10 -> old_group end, group_of: fn 1 -> new_group end]
      assert KillReward.selection(mob, 3, opts) == {:group, old_group}

      opts = Keyword.put(opts, :group, fn _id -> nil end)
      assert KillReward.selection(mob, 3, opts) == {:group, new_group}
      opts = Keyword.put(opts, :group_of, fn _guid -> nil end)
      assert KillReward.selection(mob, 3, opts) == {:solo, 1}
    end

    test "insufficient contribution credits only a player killing blow", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | damage_origin: %DamageOrigin{player: 35, npc: 65}}}
      npc = Guid.from_low_guid(:mob, 1, 1)
      pet = Guid.from_low_guid(:pet, 1, 1)
      opts = [metadata: fn guid -> if guid == pet, do: %{owner_guid: 3} end]
      assert KillReward.selection(mob, 3, opts) == {:solo, 3}
      assert KillReward.selection(mob, pet, opts) == {:solo, 3}
      assert KillReward.selection(mob, npc, opts) == nil
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

    test "includes the living original tagger after departure", %{mob: mob} do
      group = %Group{members: [%Member{guid: 2}]}

      opts = [
        nearby: fn ^mob, 74.0 -> [{1, 0}, {2, 1}, {3, 2}] end,
        metadata: fn _guid -> %{level: 10, alive?: true} end
      ]

      assert KillReward.eligible_members(mob, group, opts) == [%{guid: 1, level: 10}, %{guid: 2, level: 10}]
    end
  end

  describe "group_rewards/3" do
    test "uses the dungeon elite reward before splitting among members", %{mob: mob, opts: opts} do
      creature = %{mob.internal.creature | rank: 1}
      mob = %{mob | internal: %{mob.internal | creature: creature}}
      group = %Group{members: [%Member{guid: 1}, %Member{guid: 2}]}
      assert [%Award{xp: 95}, %Award{xp: 95}] = KillReward.group_rewards(mob, group, opts)
      opts = Keyword.put(opts, :non_raid_dungeon?, true)
      assert [%Award{xp: 119}, %Award{xp: 119}] = KillReward.group_rewards(mob, group, opts)
    end

    test "reduces the base reward before sharing it", %{mob: mob, opts: opts} do
      mob = %{mob | internal: %{mob.internal | damage_origin: %DamageOrigin{player: 50, npc: 50}}}
      group = %Group{members: [%Member{guid: 1}, %Member{guid: 2}]}
      assert [%Award{guid: 1, xp: 24}, %Award{guid: 2, xp: 24}] = KillReward.group_rewards(mob, group, opts)
    end

    test "includes the departed tagger once without crediting their new party", %{mob: mob, opts: opts} do
      group = %Group{members: [%Member{guid: 2}]}
      assert [%Award{guid: 1, xp: 47}, %Award{guid: 2, xp: 47}] = KillReward.group_rewards(mob, group, opts)
      group = %{group | members: [%Member{guid: 1}, %Member{guid: 2}]}
      assert [%Award{guid: 1, xp: 47}, %Award{guid: 2, xp: 47}] = KillReward.group_rewards(mob, group, opts)
    end

    test "finds a released member through a nearby corpse while rejecting invalid presence", %{
      mob: mob,
      world: world,
      opts: opts
    } do
      ghost_corpse = Corpse.guid_for(2)
      other_copy_corpse = Corpse.guid_for(3)
      offline_corpse = Corpse.guid_for(4)
      living_corpse = Corpse.guid_for(5)
      group = %Group{members: Enum.map(1..7, &%Member{guid: &1})}

      positions = %{
        1 => {world, 0.0, 0.0, 0.0},
        2 => {WorldRef.open(1), 999.0, 0.0, 0.0},
        ghost_corpse => {world, 74.0, 0.0, 0.0},
        3 => {world, 999.0, 0.0, 0.0},
        other_copy_corpse => {%{world | instance_id: 42}, 0.0, 0.0, 0.0},
        offline_corpse => {world, 0.0, 0.0, 0.0},
        5 => {world, 999.0, 0.0, 0.0},
        living_corpse => {world, 0.0, 0.0, 0.0},
        6 => {world, 74.01, 0.0, 0.0},
        7 => {world, 0.0, 0.0, 0.0}
      }

      opts =
        Keyword.merge(opts,
          metadata: fn
            7 -> nil
            guid -> %{level: 10, alive?: guid in [1, 5], ghost?: guid not in [1, 5]}
          end,
          position: &Map.get(positions, &1)
        )

      assert [%Award{guid: 1, xp: 95}, %Award{guid: 2, xp: 0, quest?: false}] =
               KillReward.group_rewards(mob, group, opts)
    end

    test "gives an unreleased member quest credit without reducing living XP", %{mob: mob, opts: opts} do
      group = %Group{members: [%Member{guid: 1}, %Member{guid: 2}]}
      opts = Keyword.put(opts, :metadata, fn guid -> %{level: 10, alive?: guid == 1, ghost?: false} end)

      assert [%Award{guid: 1, xp: 95}, %Award{guid: 2, xp: 0, quest?: true}] =
               KillReward.group_rewards(mob, group, opts)
    end
  end

  defp reward_context(_context) do
    world = WorldRef.open(0)

    mob = %Mob{
      unit: %Unit{level: 10},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: world,
        damage_origin: %DamageOrigin{player: 100},
        creature: %Creature{experience_multiplier: 1.0},
        loot: %Loot{tapped_by: %Tap{player: 1, group_id: 10}}
      }
    }

    opts = [
      metadata: fn _guid -> %{level: 10, alive?: true, ghost?: false} end,
      position: fn _guid -> {world, 0.0, 0.0, 0.0} end
    ]

    %{mob: mob, world: world, opts: opts}
  end
end
