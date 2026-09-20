defmodule ThistleTea.Game.Entity.Logic.Honor.LedgerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Logic.Honor.Ledger

  describe "new/2" do
    test "uses Tuesday weeks with configurable reset weekdays" do
      unix_day = Date.diff(~D[2026-09-20], ~D[1970-01-01])
      ledger = Ledger.new(unix_day)

      assert ledger.day == unix_day
      assert Date.add(~D[1970-01-01], ledger.week_start) == ~D[2026-09-15]
      assert Ledger.new(unix_day, 7).week_start == unix_day
    end
  end

  describe "register/4" do
    test "refreshes level without replacing retained honor" do
      ledger = Ledger.new(0) |> Ledger.register(1, :alliance, 50) |> Ledger.award(1, %Award{type: :bonus, points: 100})
      refreshed = Ledger.register(ledger, 1, :alliance, 51)

      assert refreshed.entries[1].level == 51
      assert refreshed.entries[1].honor == ledger.entries[1].honor
    end
  end

  describe "debug_rank_points/3" do
    test "caps at the character level and preserves highest rank and awards" do
      ledger = Ledger.new(0) |> Ledger.register(1, :alliance, 30) |> Ledger.award(1, %Award{type: :bonus, points: 100})
      ranked = Ledger.debug_rank_points(ledger, 1, 65_000)
      assert ranked.entries[1].honor.rank_points == 7_150
      assert ranked.entries[1].honor.highest_rank == 7
      demoted = Ledger.debug_rank_points(ranked, 1, 0)
      assert demoted.entries[1].honor.rank_points == 0
      assert demoted.entries[1].honor.highest_rank == 7
      assert demoted.entries[1].honor.days == ledger.entries[1].honor.days
      assert Ledger.debug_rank_points(ledger, 2, 100) == ledger
    end
  end

  describe "advance/2" do
    test "settles the complete faction pool before recording the next week's awards" do
      ledger = Ledger.new(0) |> Ledger.register(1, :alliance, 60) |> Ledger.register(2, :alliance, 60)

      ledger =
        Enum.reduce(1..15, ledger, fn _, ledger -> Ledger.award(ledger, 1, %Award{type: :honorable, points: 188}) end)

      next_week = ledger.week_start + 7
      ledger = Ledger.advance(ledger, next_week)

      assert ledger.entries[1].honor.rank_points == 3_000
      assert ledger.entries[1].honor.last_standing == 1
      assert ledger.entries[1].honor.last_week.honorable_kills == 15
      assert ledger.entries[2].honor.last_standing == 0
      assert ledger.week_start == next_week

      ledger = Ledger.award(ledger, 1, %Award{type: :bonus, points: 396})
      assert ledger.entries[1].honor.days[next_week].contribution == 396
      assert Ledger.advance(ledger, next_week) == ledger
      assert Ledger.advance(ledger, 0) == ledger
    end

    test "catches up inactive weeks and preserves lifetime kills and highest rank" do
      ledger = Ledger.new(0) |> Ledger.register(1, :alliance, 60)

      ledger =
        Enum.reduce(1..15, ledger, fn _, ledger -> Ledger.award(ledger, 1, %Award{type: :honorable, points: 188}) end)

      ledger = Ledger.advance(ledger, ledger.week_start + 21)

      honor = ledger.entries[1].honor
      assert honor.rank_points == 2_430
      assert honor.last_standing == 0
      assert honor.last_week.honorable_kills == 0
      assert honor.lifetime_honorable_kills == 15
      assert honor.highest_rank == 6
      assert honor.days == %{}
    end
  end

  describe "player_kill/4" do
    test "awards integer contribution shares and resets repeat penalties each day" do
      ledger = Ledger.new(0) |> Ledger.register(1, :alliance, 60) |> Ledger.register(2, :horde, 60)
      {ledger, first} = Ledger.player_kill(ledger, 1, 2, 0.5)
      {ledger, second} = Ledger.player_kill(ledger, 1, 2, 0.5)

      assert first.points == 94
      assert second.points == 84
      assert first.victim_rank == 5
      assert first.victim_guid == 2
      assert ledger.entries[1].honor.lifetime_honorable_kills == 2

      {ledger, next_day} = ledger |> Ledger.advance(1) |> Ledger.player_kill(1, 2, 0.5)
      assert next_day.points == first.points
      assert ledger.entries[1].honor.lifetime_honorable_kills == 3
    end

    test "rejects friendly and gray victims and exhausted repeat credit" do
      ledger =
        Ledger.new(0)
        |> Ledger.register(1, :alliance, 60)
        |> Ledger.register(2, :alliance, 60)
        |> Ledger.register(3, :horde, 51)
        |> Ledger.register(4, :horde, 60)

      assert Ledger.player_kill(ledger, 1, 2, 1) == {ledger, nil}
      assert Ledger.player_kill(ledger, 1, 3, 1) == {ledger, nil}
      assert Ledger.player_kill(ledger, 1, 5, 1) == {ledger, nil}

      ledger = Enum.reduce(1..10, ledger, fn _, ledger -> elem(Ledger.player_kill(ledger, 1, 4, 1), 0) end)
      assert Ledger.player_kill(ledger, 1, 4, 1) == {ledger, nil}
      assert ledger.entries[1].honor.lifetime_honorable_kills == 10
    end
  end
end
