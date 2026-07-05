defmodule ThistleTea.Game.Entity.Logic.RestTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Rest

  @next_level_xp 1_152_000

  defp character(attrs \\ []) do
    %Character{
      unit: %Unit{level: 10},
      player: %Player{flags: 0, next_level_xp: @next_level_xp, rest_state: 2, rest_state_experience: 0},
      internal: struct(Internal, attrs)
    }
  end

  describe "start/3 and stop/2" do
    test "sets the resting flag and rest type" do
      c = Rest.start(character(), {:tavern, 71}, 1_000)

      assert Rest.resting?(c)
      assert Rest.rest_type(c) == {:tavern, 71}
      assert (c.player.flags &&& Rest.player_flag_resting()) != 0

      c = Rest.stop(c, 2_000)

      refute Rest.resting?(c)
      assert (c.player.flags &&& Rest.player_flag_resting()) == 0
    end
  end

  describe "flush/2" do
    test "accrues next_level_xp / 1_152_000 per second while resting" do
      c = character() |> Rest.start(:city, 0) |> Rest.flush(100_000)

      assert_in_delta c.internal.rest_bonus, 100.0, 0.001
      assert c.player.rest_state_experience == 100
      assert c.internal.rest_started_at == 100_000
    end

    test "does nothing when not resting" do
      c = Rest.flush(character(), 100_000)

      assert c.internal.rest_bonus == 0.0
      assert c.player.rest_state_experience == 0
    end

    test "caps the pool at 0.75 x next_level_xp" do
      c = character() |> Rest.start(:city, 0) |> Rest.flush(2_000_000_000_000)

      assert c.internal.rest_bonus == @next_level_xp * 0.75
    end
  end

  describe "rest state byte" do
    test "flips to rested above 10 and back to normal at 1 or below" do
      c = character()

      assert Rest.set_bonus(c, 5.0).player.rest_state == 2
      assert Rest.set_bonus(c, 11.0).player.rest_state == 1

      rested = Rest.set_bonus(c, 11.0)
      assert Rest.set_bonus(rested, 5.0).player.rest_state == 1
      assert Rest.set_bonus(rested, 1.0).player.rest_state == 2
    end
  end

  describe "spend/3" do
    test "spends up to the base xp and drains the pool" do
      c = character() |> Rest.start(:city, 0) |> Rest.flush(100_000) |> Rest.stop(100_000)

      {c, bonus} = Rest.spend(c, 30, 100_000)
      assert bonus == 30
      assert c.player.rest_state_experience == 70

      {c, bonus} = Rest.spend(c, 500, 100_000)
      assert bonus == 70
      assert c.player.rest_state_experience == 0

      {_c, bonus} = Rest.spend(c, 500, 100_000)
      assert bonus == 0
    end

    test "returns zero bonus for non-positive xp" do
      assert {_c, 0} = Rest.spend(character(), 0, 100_000)
    end

    test "accrues pending rest before spending" do
      c = character() |> Rest.start(:city, 0)

      {c, bonus} = Rest.spend(c, 50, 100_000)

      assert bonus == 50
      assert c.player.rest_state_experience == 50
    end
  end
end
