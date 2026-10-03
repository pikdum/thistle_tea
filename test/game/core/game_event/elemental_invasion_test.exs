defmodule ThistleTea.Game.Core.GameEvent.ElementalInvasionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.ElementalInvasion
  alias ThistleTea.Game.Core.GameEvent.Rule

  describe "events/0" do
    test "claims the invasion, its rifts, and its lords without ever starting them" do
      assert Enum.sort(ElementalInvasion.events()) == [13, 68, 69, 70, 71, 72, 73, 74, 75]
      assert Rule.for_event(72) == ElementalInvasion
      assert ElementalInvasion.active_events(~U[2026-10-03 12:00:00Z], MapSet.new()) == []
    end
  end

  describe "invaders/1" do
    test "each stage holds one more invader per rift, up to six" do
      assert Enum.map(0..6, &ElementalInvasion.invaders/1) == [0, 3, 4, 5, 6, 6, 0]
    end
  end

  describe "slain/2" do
    test "the fiftieth invader slain raises the stage until the lord walks out" do
      assert ElementalInvasion.slain(1, 0) == {1, 1}
      assert ElementalInvasion.slain(1, 49) == {2, 0}
      assert ElementalInvasion.slain(4, 49) == {5, 0}
      assert ElementalInvasion.slain(5, 12) == {5, 12}
      assert ElementalInvasion.slain(6, 0) == {6, 0}
    end
  end

  describe "endured/1" do
    test "an hour raises a stage short of the lord" do
      assert Enum.map(1..6, &ElementalInvasion.endured/1) == [2, 3, 4, 5, 5, 6]
    end
  end

  describe "driven/2" do
    test "rifts run until their lord falls and the lord stays out while looted" do
      stages = %{fire: 5, air: 6, earth: 6, water: 2}
      events = ElementalInvasion.driven(stages, MapSet.new([:air]))

      assert events[13]
      assert {events[68], events[72]} == {true, true}
      assert {events[69], events[73]} == {false, true}
      assert {events[70], events[74]} == {false, false}
      assert {events[71], events[75]} == {true, false}
    end

    test "the invasion ends once every lord has fallen and been looted" do
      fallen = %{fire: 6, air: 6, earth: 6, water: 6}

      assert ElementalInvasion.driven(fallen, MapSet.new([:water]))[13]
      events = ElementalInvasion.driven(fallen, MapSet.new())
      assert Enum.all?(events, fn {_event, active?} -> not active? end)
    end
  end
end
