defmodule ThistleTea.Game.Entity.Logic.Honor.RankTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Honor.Candidate
  alias ThistleTea.Game.Entity.Logic.Honor.Rank

  describe "number/1" do
    test "uses the client's rank offset and vanilla point thresholds" do
      assert Rank.number(0) == 0
      assert Rank.number(1) == 5
      assert Rank.number(1_999) == 5
      assert Rank.number(2_000) == 6
      assert Rank.number(4_999) == 6
      assert Rank.number(5_000) == 7
      assert Rank.number(59_999) == 17
      assert Rank.number(60_000) == 18
      assert Rank.number(65_000) == 18
      assert Rank.visual(60_000) == 14
    end
  end

  describe "progress/1" do
    test "resets at a rank boundary and caps the highest-rank bar" do
      assert Rank.progress(0) == 0
      assert Rank.progress(1_000) == 127
      assert Rank.progress(2_000) == 0
      assert Rank.progress(3_500) == 127
      assert Rank.progress(5_000) == 0
      assert Rank.progress(65_000) == 255
    end
  end

  describe "decay/2" do
    test "uses twenty percent decay, halves losses, and caps weekly loss" do
      assert Rank.decay(10_000, 3_000) == 11_000
      assert Rank.decay(10_000, 0) == 9_000
      assert Rank.decay(60_000, 0) == 57_500
      assert Rank.decay(0, 0) == 0
      assert Rank.decay(3, 0) == 2.5
    end
  end

  describe "maximum/1" do
    test "uses the level restrictions through level sixty" do
      assert Enum.map([29, 30, 35, 36, 39, 40, 43, 44, 52, 53, 60], &Rank.maximum/1) ==
               [6_500, 7_150, 12_025, 13_325, 17_225, 18_850, 23_725, 26_000, 44_200, 46_800, 65_000]
    end
  end

  describe "weekly/1" do
    test "requires fifteen kills and ranks factions independently" do
      candidates = [
        candidate(1, :alliance, 1_000),
        candidate(2, :horde, 2_000),
        %{candidate(3, :alliance, 10_000) | honorable_kills: 14, rank_points: 20_000}
      ]

      standings = Rank.weekly(candidates)

      assert standings[1].position == 1
      assert standings[2].position == 1
      assert standings[1].earning == 3_000
      assert standings[2].earning == 3_000
      assert standings[3].position == 0
      assert standings[3].earning == 0
      assert standings[3].rank_points == 18_000
    end

    test "interpolates within the full faction pool" do
      candidates = for position <- 1..1_000, do: candidate(position, :alliance, 1_001 - position)
      standings = Rank.weekly(candidates)

      assert standings[1].earning == 13_000
      assert standings[1_000].earning < 3
      assert standings[500].earning > 2_000
      assert standings[500].earning < 3_000
      assert standings[1].rank_points == 13_000
      assert standings[1_000].position == 1_000
    end

    test "equal contributions earn equal points with deterministic standings" do
      candidates = for guid <- 1..100, do: candidate(guid, :alliance, 500)
      standings = Rank.weekly(Enum.reverse(candidates))

      assert standings == Rank.weekly(candidates)
      assert standings[1].position == 1
      assert standings[100].position == 100
      assert standings |> Map.values() |> Enum.map(& &1.earning) |> Enum.uniq() |> length() == 1
    end

    test "caps active rank points by level after earnings and decay" do
      candidates = for guid <- 1..1_000, do: %{candidate(guid, :alliance, 1_001 - guid) | level: 29}

      assert Rank.weekly(candidates)[1].rank_points == 6_500
    end
  end

  defp candidate(guid, team, contribution) do
    %Candidate{guid: guid, team: team, level: 60, honorable_kills: 15, contribution: contribution}
  end
end
