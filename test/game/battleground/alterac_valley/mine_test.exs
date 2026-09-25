defmodule ThistleTea.Game.Battleground.AlteracValley.MineTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.AlteracValley.Mine

  describe "capture/3" do
    test "supplies follow the owner and redundant captures do not extend the timer" do
      for {_id, mine} <- Mine.all() do
        refute Mine.supply_allowed?(mine, :alliance)
        refute Mine.supply_allowed?(mine, :horde)
        {:captured, alliance} = Mine.capture(mine, :alliance, 100)
        assert alliance.reclaim_at == 1_200_100
        assert Mine.supply_allowed?(alliance, :alliance)
        refute Mine.supply_allowed?(alliance, :horde)
        assert {:unchanged, ^alliance} = Mine.capture(alliance, :alliance, 500)
        {:captured, horde} = Mine.capture(alliance, :horde, 1_200_000)
        assert horde.reclaim_at == 2_400_000
        assert Mine.supply_allowed?(horde, :horde)
        refute Mine.supply_allowed?(horde, :alliance)
      end
    end
  end

  describe "reclaim/3" do
    test "reclaims after twenty minutes and ignores earlier ownership timers" do
      {:captured, alliance} = Mine.capture(%Mine{id: 0}, :alliance, 0)
      {:captured, horde} = Mine.capture(alliance, :horde, 1_000_000)
      assert {:unchanged, ^horde} = Mine.reclaim(horde, alliance.revision, 1_200_000)
      assert {:unchanged, ^horde} = Mine.reclaim(horde, horde.revision, 2_199_999)
      {:reclaimed, neutral} = Mine.reclaim(horde, horde.revision, 2_200_000)
      assert neutral.owner == nil
      assert neutral.reclaim_at == nil
      assert Mine.event_state(neutral) == 2
      refute Mine.supply_allowed?(neutral, :horde)
      assert {:unchanged, ^neutral} = Mine.reclaim(neutral, horde.revision, 2_300_000)
    end
  end

  describe "events/1" do
    test "bosses and population share ownership and map fields clear on each transition" do
      for {id, neutral} <- Mine.all() do
        {:captured, alliance} = Mine.capture(neutral, :alliance, 0)
        {:captured, horde} = Mine.capture(alliance, :horde, 1)

        for {mine, state} <- [{neutral, 2}, {alliance, 0}, {horde, 1}] do
          assert Mine.events(mine) == [{46 + id, state}, {50 + id, state}]
          fields = Mine.world_states(mine)
          assert length(fields) == 3
          assert Enum.count(fields, fn {_field, value} -> value == 1 end) == 1
          first_field = if id == 0, do: 1_358, else: 1_355
          assert {first_field + state, 1} in fields
        end
      end
    end
  end
end
