defmodule ThistleTea.Game.Entity.Logic.RestTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.AI.Tick
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

    test "a backward timestamp cannot credit the same time twice" do
      c = character() |> Rest.start(:city, -100_000) |> Rest.flush(-50_000)
      c = c |> Rest.flush(-80_000) |> Rest.flush(-50_000)
      assert c.internal.rest_bonus == 50.0
      assert c.internal.rest_started_at == -50_000
    end
  end

  describe "logout/2 and restore/2" do
    test "settles online time and credits an offline rest-area interval once" do
      for location <- [:city, {:tavern, 71}] do
        offline = character() |> Rest.start(location, -200_000) |> Rest.logout(-100_000)
        assert offline.internal.rest_bonus == 100.0
        assert offline.internal.rest_started_at == nil
        assert offline.internal.rest_logout_at == -100_000
        assert Rest.logout(offline, 0) == offline
        assert Rest.flush(offline, 0) == offline

        restored = Rest.restore(offline, 0)
        assert restored.internal.rest_bonus == 200.0
        assert restored.player.rest_state_experience == 200
        assert restored.player.rest_state == 1
        assert restored.internal.rest_logout_at == nil
        assert restored.internal.rest_started_at == 0
        assert Rest.restore(restored, 100_000) == restored
        assert Rest.flush(restored, 100_000).internal.rest_bonus == 300.0
      end
    end

    test "wilderness time earns one quarter of the rest-area rate" do
      offline = Rest.logout(character(), 0)
      restored = Rest.restore(offline, 100_000)
      assert restored.internal.rest_bonus == 25.0
      assert restored.internal.rest_started_at == nil
      assert Rest.flush(restored, 200_000) == restored
      refute Rest.resting?(restored)
    end

    test "offline growth preserves fractions and obeys the pool cap" do
      offline = character() |> Rest.set_bonus(0.25) |> Rest.logout(0)
      assert Rest.restore(offline, 1_000).internal.rest_bonus == 0.5
      assert Rest.restore(offline, 10_000_000_000).internal.rest_bonus == @next_level_xp * 0.75
    end

    test "fresh characters and backward offline timestamps receive no bonus" do
      assert Rest.restore(character(), 100_000) == character()
      restored = character() |> Rest.logout(1_000) |> Rest.restore(0)
      assert restored.internal.rest_bonus == 0.0
      assert restored.internal.rest_logout_at == nil
    end

    test "a character with no next level cannot accumulate a bonus" do
      capped = %{character() | player: %{character().player | next_level_xp: 0}}
      restored = capped |> Rest.start(:city, 0) |> Rest.logout(10_000) |> Rest.restore(100_000)
      assert restored.internal.rest_bonus == 0.0
      assert restored.player.rest_state_experience == 0
      assert Rest.next_tick_at(restored) == nil
    end
  end

  describe "tick/2" do
    test "publishes rest growth through the player tree on a ten-second deadline" do
      c = character() |> Rest.start(:city, 0)
      assert Tick.needs_tick?(c)
      assert Tick.player_delay(c, :running, 2_000) == 8_000
      assert Rest.tick(c, 9_999) == c

      {_, updated} = BT.tick(PlayerBT.tree(), c, Context.new(10_000))
      assert updated.internal.rest_bonus == 10.0
      assert updated.player.rest_state_experience == 10
      assert updated.internal.broadcast_update?
      assert Rest.next_tick_at(updated) == 20_000
    end

    test "stops rest scheduling at the cap, outside rest areas, and while offline" do
      c = character() |> Rest.start(:city, 0)
      assert Rest.next_tick_at(Rest.set_bonus(c, @next_level_xp)) == nil
      assert Rest.next_tick_at(Rest.stop(c, 1_000)) == nil
      assert Rest.next_tick_at(Rest.logout(c, 1_000)) == nil
      assert Rest.tick(Rest.logout(c, 1_000), 100_000).internal.rest_bonus == 1.0
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
