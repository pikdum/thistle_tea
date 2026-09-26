defmodule ThistleTea.Game.Entity.Logic.GroupRewardTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.GroupReward
  alias ThistleTea.Game.Entity.Logic.GroupReward.Award
  alias ThistleTea.Game.Entity.Logic.GroupReward.Member

  describe "plan/3" do
    test "separates living XP, unreleased quest credit, and ghost reputation recipients" do
      members = [
        %Member{guid: 1, level: 10, alive?: true, original_tagger?: true},
        %Member{guid: 2, level: 10},
        %Member{guid: 3, level: 10, ghost?: true}
      ]

      assert GroupReward.plan(members, 10) == [
               %Award{guid: 1, xp: 95, pet_xp: 95, pet_max_level: 10, quest?: true},
               %Award{guid: 2, quest?: true},
               %Award{guid: 3}
             ]
    end

    test "retains the original dead tagger in the XP denominator" do
      members = [
        %Member{guid: 1, level: 10, original_tagger?: true},
        %Member{guid: 2, level: 10, alive?: true},
        %Member{guid: 3, level: 60}
      ]

      assert [%Award{xp: 0}, %Award{xp: 47}, %Award{xp: 0}] = GroupReward.plan(members, 10)
    end

    test "requires a nearby living contributor or the original tagger" do
      assert GroupReward.plan([%Member{guid: 1, level: 10}], 10) == []

      assert GroupReward.plan([%Member{guid: 1, level: 10, original_tagger?: true}], 10) == [
               %Award{guid: 1, quest?: true}
             ]
    end

    test "keeps a gray owner's pet share independently of player XP" do
      members = [%Member{guid: 1, level: 60, alive?: true}, %Member{guid: 2, level: 20, alive?: true}]
      assert [%Award{xp: 0, pet_xp: 58, pet_max_level: 20}, %Award{xp: 20}] = GroupReward.plan(members, 21)
    end

    test "grants quest and reputation eligibility for gray and no-XP kills" do
      member = %Member{guid: 1, level: 60, alive?: true}
      assert [%Award{xp: 0, pet_xp: 0, quest?: true}] = GroupReward.plan([member], 1)
      assert [%Award{xp: 0, pet_xp: 0, quest?: true}] = GroupReward.plan([member], 60, no_xp?: true)
    end
  end

  describe "for_recipient/2" do
    test "rechecks death and release without restoring ineligible rewards after resurrection" do
      award = %Award{xp: 40, pet_xp: 40, pet_max_level: 10, quest?: true}
      dead = %Character{unit: %Unit{health: 0}, player: %Player{flags: 0}}
      ghost = %{dead | unit: %{dead.unit | health: 1}, player: %{dead.player | flags: 0x10}}
      alive = %{dead | unit: %{dead.unit | health: 100}}

      assert %Award{xp: 0, pet_xp: 0, quest?: true} = GroupReward.for_recipient(award, dead)
      assert %Award{xp: 0, pet_xp: 0, quest?: false} = GroupReward.for_recipient(award, ghost)
      assert GroupReward.for_recipient(award, alive) == award
      assert GroupReward.for_recipient(%Award{}, alive) == %Award{}
    end
  end
end
