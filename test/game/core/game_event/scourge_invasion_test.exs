defmodule ThistleTea.Game.Core.GameEvent.ScourgeInvasionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.Rule
  alias ThistleTea.Game.Core.GameEvent.ScourgeInvasion
  alias ThistleTea.Game.Core.Rolls

  @now 1_800_000_000
  @rolls Rolls.fixed(attack_delay: 3_000)

  describe "events/0" do
    test "claims the invasion, its zones, and its milestones without ever starting them" do
      assert Enum.sort(ScourgeInvasion.events()) == [17 | Enum.to_list(90..99)]
      assert Rule.for_event(94) == ScourgeInvasion
      assert ScourgeInvasion.active_events(~U[2026-10-03 12:00:00Z], MapSet.new()) == []
    end
  end

  describe "begin/3" do
    test "the first wave strikes every zone at once" do
      {variables, active, actions} = ScourgeInvasion.begin(%{}, MapSet.new(), @now)

      assert MapSet.size(active) == 6
      assert Enum.map(actions, fn {:start, zone} -> zone.name end) == Enum.map(ScourgeInvasion.zones(), & &1.name)
      assert ScourgeInvasion.remaining(variables, ScourgeInvasion.zone(:winterspring)) == 3
      assert ScourgeInvasion.remaining(variables, ScourgeInvasion.zone(:azshara)) == 2
    end

    test "after a victory only two zones fall at once, and never the last one won" do
      {_variables, active, _actions} = ScourgeInvasion.begin(%{17_000 => 1, 17_001 => 618}, MapSet.new(), @now)

      assert MapSet.equal?(active, MapSet.new([:tanaris, :azshara]))
    end
  end

  describe "update/4" do
    test "a zone whose necropolises have all fallen is won and rests" do
      tanaris = ScourgeInvasion.zone(:tanaris)
      variables = Map.put(besieged(), tanaris.remaining_variable, 0)

      {variables, active, actions} = ScourgeInvasion.update(variables, all_zones(), @now, @rolls)

      assert actions == [{:stop, tanaris}]
      refute :tanaris in active
      assert ScourgeInvasion.victories(variables) == 1
      assert ScourgeInvasion.attack_time(variables, tanaris) == @now + 3_000
      assert Map.fetch!(variables, 17_001) == 440
    end

    test "zones still holding necropolises fight on" do
      variables = besieged()

      assert {^variables, _active, []} = ScourgeInvasion.update(variables, all_zones(), @now, @rolls)
    end

    test "after a victory a zone waits while more than one other is under attack" do
      azshara = ScourgeInvasion.zone(:azshara)
      active = MapSet.new([:winterspring, :tanaris])
      variables = Map.merge(besieged(), %{17_000 => 1, azshara.remaining_variable => 0})

      {variables, active, actions} = ScourgeInvasion.update(variables, active, @now, @rolls)

      assert actions == []
      assert MapSet.size(active) == 2
      assert ScourgeInvasion.attack_time(variables, azshara) == @now + 3_000
    end

    test "with one zone under attack another may fall, but never the last one won" do
      variables = Map.merge(besieged(), %{17_000 => 1, 17_001 => 440})

      {_variables, active, actions} = ScourgeInvasion.update(variables, MapSet.new([:winterspring]), @now, @rolls)

      assert [{:start, %{name: :azshara}}] = actions
      assert MapSet.equal?(active, MapSet.new([:winterspring, :azshara]))
    end

    test "a resting zone stays clear until its time comes" do
      azshara = ScourgeInvasion.zone(:azshara)
      variables = for zone <- ScourgeInvasion.zones(), into: %{17_000 => 1}, do: {zone.attack_time_variable, @now + 60}

      assert {^variables, _active, []} = ScourgeInvasion.update(variables, MapSet.new(), @now, @rolls)

      later = Map.put(variables, azshara.attack_time_variable, @now - 1)
      assert {_variables, _active, [{:start, ^azshara}]} = ScourgeInvasion.update(later, MapSet.new(), @now, @rolls)
    end
  end

  describe "necropolis_fell/2" do
    test "counts one necropolis down and never below none" do
      azshara = ScourgeInvasion.zone(:azshara)
      variables = ScourgeInvasion.start(%{}, azshara)

      variables = ScourgeInvasion.necropolis_fell(variables, azshara)
      assert ScourgeInvasion.remaining(variables, azshara) == 1

      variables = variables |> ScourgeInvasion.necropolis_fell(azshara) |> ScourgeInvasion.necropolis_fell(azshara)
      assert ScourgeInvasion.remaining(variables, azshara) == 0
    end
  end

  describe "driven/3" do
    test "holds the invasion and its attacked zones open while enabled" do
      events = ScourgeInvasion.driven(%{}, MapSet.new([:tanaris]), true)

      assert events[17]
      assert events[91]
      refute events[90]
      refute events[96]
      refute ScourgeInvasion.driven(%{}, MapSet.new([:tanaris]), false)[91]
    end

    test "victories open the Argent Dawn milestones and the hundred and fiftieth ends the invasion" do
      assert milestones(49) == [17]
      assert milestones(50) == [17, 96]
      assert milestones(100) == [17, 97]
      assert milestones(150) == [98, 99]
    end
  end

  describe "world_states/1" do
    test "shows each zone's map icon, its necropolises left, and the battles won" do
      winterspring = ScourgeInvasion.zone(:winterspring)
      states = Map.new(ScourgeInvasion.world_states(%{17_000 => 12, winterspring.remaining_variable => 3}))

      assert states[2219] == 12
      assert states[2259] == 1
      assert states[2284] == 3
      assert states[2263] == 0
      assert states[2283] == 0
    end
  end

  defp all_zones, do: MapSet.new(ScourgeInvasion.zones(), & &1.name)

  defp besieged do
    Enum.reduce(ScourgeInvasion.zones(), %{}, fn zone, variables ->
      variables |> ScourgeInvasion.start(zone) |> Map.put(zone.attack_time_variable, @now - 10)
    end)
  end

  defp milestones(victories) do
    for {event, true} <- ScourgeInvasion.driven(%{17_000 => victories}, MapSet.new(), true), do: event
  end
end
