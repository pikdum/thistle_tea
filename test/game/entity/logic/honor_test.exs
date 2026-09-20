defmodule ThistleTea.Game.Entity.Logic.HonorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Honor
  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Data.Honor.Standing
  alias ThistleTea.Game.Entity.Logic.Honor, as: HonorLogic

  describe "kill_points/4" do
    test "scales with the killer's level bracket and the victim's visual rank" do
      assert_in_delta HonorLogic.kill_points(60, 60, 0), 188.3, 0.001
      assert_in_delta HonorLogic.kill_points(50, 50, 0), 179.73235, 0.001
      assert_in_delta HonorLogic.kill_points(40, 40, 0), 107.46281, 0.001
      assert_in_delta HonorLogic.kill_points(30, 30, 0), 64.66222, 0.001
      assert_in_delta HonorLogic.kill_points(20, 20, 0), 38.9781, 0.001
      assert_in_delta HonorLogic.kill_points(19, 19, 0), 22.8220, 0.001
      assert HonorLogic.kill_points(60, 60, 14) > HonorLogic.kill_points(60, 60, 1)
    end

    test "reduces repeat credit by ten percent and stops after ten kills" do
      for previous <- 0..9 do
        assert_in_delta HonorLogic.kill_points(60, 60, 0, previous), 188.3 * (10 - previous) / 10, 0.001
      end

      assert HonorLogic.kill_points(60, 60, 0, 10) == 0
      assert HonorLogic.kill_points(60, 60, 0, 20) == 0
    end

    test "rejects gray victims and caps the bonus for higher level victims" do
      assert HonorLogic.kill_points(60, 51, 0) == 0
      assert_in_delta HonorLogic.kill_points(60, 52, 0), 188.3 * 9 / 17, 0.001
      assert_in_delta HonorLogic.kill_points(50, 52, 0), 179.73235 * 1.1, 0.001
      assert_in_delta HonorLogic.kill_points(50, 60, 0), 179.73235 * 1.2, 0.001
    end
  end

  describe "dishonorable_points/1" do
    test "uses the vanilla level bands and caps the immediate penalty" do
      assert HonorLogic.dishonorable_points(29) == 10
      assert HonorLogic.dishonorable_points(30) == 11.5
      assert HonorLogic.dishonorable_points(35) == 19
      assert HonorLogic.dishonorable_points(36) == 21
      assert HonorLogic.dishonorable_points(41) == 31
      assert_in_delta HonorLogic.dishonorable_points(50), 59.8, 0.001
      assert HonorLogic.dishonorable_points(51) == 64
      assert HonorLogic.dishonorable_points(60) == 100
    end
  end

  describe "award/3" do
    test "counts honorable kills and independent victims by game day" do
      award = %Award{type: :honorable, points: 188, victim_key: {:player, 7}}

      honor =
        %Honor{}
        |> HonorLogic.award(award, 100)
        |> HonorLogic.award(%{award | points: 169}, 100)
        |> HonorLogic.award(%{award | victim_key: {:player, 8}}, 100)
        |> HonorLogic.award(award, 101)

      assert honor.lifetime_honorable_kills == 4
      assert HonorLogic.victim_kills(honor, 100, {:player, 7}) == 2
      assert HonorLogic.victim_kills(honor, 100, {:player, 8}) == 1
      assert HonorLogic.victim_kills(honor, 101, {:player, 7}) == 1
      assert HonorLogic.victim_kills(honor, 102, {:player, 7}) == 0
      assert honor.days[100].contribution == 545
    end

    test "bonus honor does not add a kill or consume a repeat-victim credit" do
      honor = HonorLogic.award(%Honor{}, %Award{type: :bonus, points: 396}, 100)

      assert honor.days[100].contribution == 396
      assert honor.days[100].honorable_kills == 0
      assert honor.lifetime_honorable_kills == 0
      assert honor.days[100].victims == %{}
    end

    test "dishonorable kills reduce rank immediately without reducing weekly contribution" do
      honor = %Honor{rank_points: 5_050, highest_rank: 7}
      honor = HonorLogic.award(honor, %Award{type: :honorable, points: 188}, 100)
      honor = HonorLogic.award(honor, %Award{type: :dishonorable, points: 100}, 100)

      assert honor.rank_points == 4_950
      assert honor.highest_rank == 7
      assert honor.lifetime_dishonorable_kills == 1
      assert honor.days[100].contribution == 188
      assert honor.days[100].dishonorable_kills == 1

      honor = HonorLogic.award(%{honor | rank_points: 50}, %Award{type: :dishonorable, points: 100}, 100)
      assert honor.rank_points == 0
    end

    test "zero-value awards do not create phantom kills" do
      assert HonorLogic.award(%Honor{}, %Award{type: :honorable, points: 0}, 100) == %Honor{}
    end
  end

  describe "project/4" do
    test "projects daily, weekly and lifetime totals while preserving unrelated fields" do
      honor =
        %Honor{rank_points: 3_500, highest_rank: 8}
        |> HonorLogic.award(%Award{type: :honorable, points: 188.8}, 100)
        |> HonorLogic.award(%Award{type: :honorable, points: 169.2}, 101)
        |> HonorLogic.award(%Award{type: :dishonorable, points: 100}, 101)
        |> HonorLogic.award(%Award{type: :bonus, points: 396}, 101)

      player = HonorLogic.project(honor, %Player{coinage: 123, flags: 512}, 101, 98)

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

      player = HonorLogic.project(honor, player, 103, 98)
      assert player.session_kills == 0
      assert player.yesterday_kills == 0
      assert player.this_week_kills == 2
    end
  end

  describe "settle/3" do
    test "settles once and retains yesterday and new-week credit" do
      honor =
        %Honor{}
        |> HonorLogic.award(%Award{type: :honorable, points: 100}, 98)
        |> HonorLogic.award(%Award{type: :honorable, points: 200}, 104)
        |> HonorLogic.award(%Award{type: :bonus, points: 396}, 105)

      standing = %Standing{rank_points: 3_000, position: 1, earning: 3_000}
      honor = HonorLogic.settle(honor, 98, standing)
      player = HonorLogic.project(honor, %Player{}, 105, 105)

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
      assert HonorLogic.settle(honor, 98, %{standing | rank_points: 0}) == honor

      honor = HonorLogic.settle(honor, 105, %Standing{rank_points: 2_700})
      assert honor.last_week.honorable_kills == 0
      assert honor.last_week.contribution == 396
      assert honor.last_standing == 0
      assert honor.lifetime_honorable_kills == 2
    end
  end
end
