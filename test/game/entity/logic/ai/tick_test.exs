defmodule ThistleTea.Game.Entity.Logic.AI.TickTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Spell.Cast

  describe "mob_delay/1" do
    test "uses the tree's running delay" do
      assert Tick.mob_delay({:running, 250}) == 250
    end

    test "honors long self-paced sleeps" do
      assert Tick.mob_delay({:running, 30_000}) == 30_000
    end

    test "defaults without a self-paced delay" do
      assert Tick.mob_delay(:running) == 100
      assert Tick.mob_delay(:success) == 100
    end
  end

  describe "needs_tick?/1" do
    test "ticks while casting" do
      assert Tick.needs_tick?(fixture(casting: %Cast{}))
    end

    test "ticks while in combat with a target" do
      assert Tick.needs_tick?(fixture(in_combat: true, target: 42))
    end

    test "ticks with active auras" do
      assert Tick.needs_tick?(fixture(auras: [:aura]))
    end

    test "ticks while regenerating" do
      assert Tick.needs_tick?(fixture(health: 10))
    end

    test "idles at full resources with nothing active" do
      refute Tick.needs_tick?(fixture())
    end
  end

  describe "player_delay/3" do
    test "uses the tree's running delay when no regen is due sooner" do
      character = fixture(in_combat: true, target: 42)

      assert Tick.player_delay(character, {:running, 400}, 1_000) == 400
    end

    test "wakes for regen before a long running delay" do
      character = fixture(health: 10, blackboard: %{next_regen_at: 1_200})

      assert Tick.player_delay(character, {:running, 2_000}, 1_000) == 200
    end

    test "active combat falls back to the default cadence" do
      character = fixture(in_combat: true, target: 42)

      assert Tick.player_delay(character, :success, 1_000) == 100
    end

    test "passive regen sleeps until the next regen tick" do
      character = fixture(health: 10, blackboard: %{next_regen_at: 3_500})

      assert Tick.player_delay(character, :success, 1_000) == 2_500
    end
  end

  defp fixture(opts \\ []) do
    %Character{
      unit: %Unit{
        health: Keyword.get(opts, :health, 100),
        max_health: 100,
        power1: 100,
        max_power1: 100,
        target: Keyword.get(opts, :target, 0),
        auras: Keyword.get(opts, :auras, [])
      },
      internal: %Internal{
        casting: Keyword.get(opts, :casting),
        in_combat: Keyword.get(opts, :in_combat, false),
        blackboard: Keyword.get(opts, :blackboard)
      }
    }
  end
end
