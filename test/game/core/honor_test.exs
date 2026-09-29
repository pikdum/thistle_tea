defmodule ThistleTea.Game.Core.HonorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Honor
  alias ThistleTea.Game.Core.Honor.Award
  alias ThistleTea.Game.Core.Honor.Standing

  describe "kill_points/4" do
    test "scales with the killer's level bracket and the victim's visual rank" do
      assert_in_delta Honor.kill_points(60, 60, 0), 188.3, 0.001
      assert_in_delta Honor.kill_points(50, 50, 0), 179.73235, 0.001
      assert_in_delta Honor.kill_points(40, 40, 0), 107.46281, 0.001
      assert_in_delta Honor.kill_points(30, 30, 0), 64.66222, 0.001
      assert_in_delta Honor.kill_points(20, 20, 0), 38.9781, 0.001
      assert_in_delta Honor.kill_points(19, 19, 0), 22.8220, 0.001
      assert Honor.kill_points(60, 60, 14) > Honor.kill_points(60, 60, 1)
    end

    test "reduces repeat credit by ten percent and stops after ten kills" do
      for previous <- 0..9 do
        assert_in_delta Honor.kill_points(60, 60, 0, previous), 188.3 * (10 - previous) / 10, 0.001
      end

      assert Honor.kill_points(60, 60, 0, 10) == 0
      assert Honor.kill_points(60, 60, 0, 20) == 0
    end

    test "rejects gray victims and caps the bonus for higher level victims" do
      assert Honor.kill_points(60, 51, 0) == 0
      assert_in_delta Honor.kill_points(60, 52, 0), 188.3 * 9 / 17, 0.001
      assert_in_delta Honor.kill_points(50, 52, 0), 179.73235 * 1.1, 0.001
      assert_in_delta Honor.kill_points(50, 60, 0), 179.73235 * 1.2, 0.001
    end
  end

  describe "dishonorable_points/1" do
    test "uses the vanilla level bands and caps the immediate penalty" do
      assert Honor.dishonorable_points(29) == 10
      assert Honor.dishonorable_points(30) == 11.5
      assert Honor.dishonorable_points(35) == 19
      assert Honor.dishonorable_points(36) == 21
      assert Honor.dishonorable_points(41) == 31
      assert_in_delta Honor.dishonorable_points(50), 59.8, 0.001
      assert Honor.dishonorable_points(51) == 64
      assert Honor.dishonorable_points(60) == 100
    end
  end

  describe "award/3" do
    test "counts honorable kills and independent victims by game day" do
      award = %Award{type: :honorable, points: 188, victim_key: {:player, 7}}

      honor =
        %Honor{}
        |> Honor.award(award, 100)
        |> Honor.award(%{award | points: 169}, 100)
        |> Honor.award(%{award | victim_key: {:player, 8}}, 100)
        |> Honor.award(award, 101)

      assert honor.lifetime_honorable_kills == 4
      assert Honor.victim_kills(honor, 100, {:player, 7}) == 2
      assert Honor.victim_kills(honor, 100, {:player, 8}) == 1
      assert Honor.victim_kills(honor, 101, {:player, 7}) == 1
      assert Honor.victim_kills(honor, 102, {:player, 7}) == 0
      assert honor.days[100].contribution == 545
    end

    test "bonus honor does not add a kill or consume a repeat-victim credit" do
      honor = Honor.award(%Honor{}, %Award{type: :bonus, points: 396}, 100)

      assert honor.days[100].contribution == 396
      assert honor.days[100].honorable_kills == 0
      assert honor.lifetime_honorable_kills == 0
      assert honor.days[100].victims == %{}
    end

    test "dishonorable kills reduce rank immediately without reducing weekly contribution" do
      honor = %Honor{rank_points: 5_050, highest_rank: 7}
      honor = Honor.award(honor, %Award{type: :honorable, points: 188}, 100)
      honor = Honor.award(honor, %Award{type: :dishonorable, points: 100}, 100)

      assert honor.rank_points == 4_950
      assert honor.highest_rank == 7
      assert honor.lifetime_dishonorable_kills == 1
      assert honor.days[100].contribution == 188
      assert honor.days[100].dishonorable_kills == 1

      honor = Honor.award(%{honor | rank_points: 50}, %Award{type: :dishonorable, points: 100}, 100)
      assert honor.rank_points == 0
    end

    test "zero-value awards do not create phantom kills" do
      assert Honor.award(%Honor{}, %Award{type: :honorable, points: 0}, 100) == %Honor{}
    end
  end

  describe "project/4" do
    test "projects daily, weekly and lifetime totals while preserving unrelated fields" do
      honor =
        %Honor{rank_points: 3_500, highest_rank: 8}
        |> Honor.award(%Award{type: :honorable, points: 188.8}, 100)
        |> Honor.award(%Award{type: :honorable, points: 169.2}, 101)
        |> Honor.award(%Award{type: :dishonorable, points: 100}, 101)
        |> Honor.award(%Award{type: :bonus, points: 396}, 101)

      player = Honor.project(honor, %Player{coinage: 123, flags: 512}, 101, 98)

      assert player.session_kills == 0x00010001
      assert player.yesterday_kills == 1
      assert player.yesterday_contribution == 188
      assert player.this_week_kills == 2
      assert player.this_week_contribution == 754
      assert player.lifetime_honorable_kills == 2
      assert player.lifetime_dishonorable_kills == 1
      assert player.honor_rank == 6
      assert player.highest_honor_rank == 8
      assert player.honor_rank_bar == 119
      assert player.coinage == 123
      assert player.flags == 512

      player = Honor.project(honor, player, 103, 98)
      assert player.session_kills == 0
      assert player.yesterday_kills == 0
      assert player.this_week_kills == 2
    end
  end

  describe "settle/3" do
    test "settles once and retains yesterday and new-week credit" do
      honor =
        %Honor{}
        |> Honor.award(%Award{type: :honorable, points: 100}, 98)
        |> Honor.award(%Award{type: :honorable, points: 200}, 104)
        |> Honor.award(%Award{type: :bonus, points: 396}, 105)

      standing = %Standing{rank_points: 3_000, position: 1, earning: 3_000}
      honor = Honor.settle(honor, 98, standing)
      player = Honor.project(honor, %Player{}, 105, 105)

      assert player.last_week_kills == 2
      assert player.last_week_contribution == 300
      assert player.last_week_rank == 1
      assert player.yesterday_contribution == 200
      assert player.this_week_kills == 0
      assert player.this_week_contribution == 396
      assert player.lifetime_honorable_kills == 2
      assert player.honor_rank == 6
      assert honor.highest_rank == 6
      refute Map.has_key?(honor.days, 98)
      assert Honor.settle(honor, 98, %{standing | rank_points: 0}) == honor

      honor = Honor.settle(honor, 105, %Standing{rank_points: 2_700})
      assert honor.last_week.honorable_kills == 0
      assert honor.last_week.contribution == 396
      assert honor.last_standing == 0
      assert honor.lifetime_honorable_kills == 2
    end
  end
end
