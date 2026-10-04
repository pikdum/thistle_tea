defmodule ThistleTea.Game.Core.Battleground.AlteracValley.AirTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Air
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Template
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:active_match]

  describe "interact/5" do
    test "a friendly rescue departs once and donations wait for arrival", context do
      for {team, entry, quest, _goal, _reputation} <- commanders() do
        guid = context[team]
        assert %{effects: [], match: match} = AlteracValley.quest_rewarded(context.match, guid, quest)
        assert match == context.match

        assert {:close, departing} = AlteracValley.interact(match, guid, entry, :rescue_commander, 0)
        assert departing.match.air[entry].phase == :returning
        assert [%Effects.RunCreatureScript{creature_entry: ^entry}] = departing.effects
        assert {:close, %{effects: []}} = AlteracValley.interact(departing.match, guid, entry, :rescue_commander, 0)
        assert %{effects: []} = AlteracValley.quest_rewarded(departing.match, guid, quest)

        arrived = AlteracValley.creature_event(departing.match, entry, 1).match
        assert arrived.air[entry].phase == :ready

        assert {:unhandled, %{match: ^arrived, effects: []}} =
                 AlteracValley.interact(arrived, guid, entry, :rescue_commander, 0)
      end
    end

    test "wrong teams, invited players and inactive matches cannot rescue", context do
      for {guid, entry} <- [
            {context.horde, 13_438},
            {context.alliance, 13_179},
            {context.invited, 13_438},
            {Unique.integer(), 13_438}
          ] do
        assert {:close, %{match: match, effects: []}} =
                 AlteracValley.interact(context.match, guid, entry, :rescue_commander, 0)

        assert match == context.match
      end

      for phase <- [:countdown, {:ended, :alliance}] do
        match = %{context.match | phase: phase}

        assert {:close, %{match: ^match, effects: []}} =
                 AlteracValley.interact(match, context.alliance, 13_438, :rescue_commander, 0)
      end
    end
  end

  describe "quest_rewarded/3" do
    test "all six fleets count their own supplies and announce each goal once", context do
      for {team, entry, quest, goal, reputation} <- commanders() do
        guid = context[team]
        {:close, departure} = AlteracValley.interact(context.match, guid, entry, :rescue_commander, 0)
        match = AlteracValley.creature_event(departure.match, entry, 1).match
        before_goal = put_in(match.air[entry], %Air{phase: :ready, count: goal - 1})
        result = AlteracValley.quest_rewarded(before_goal, guid, quest)
        assert result.match.air[entry].count == goal
        faction = if team == :alliance, do: 730, else: 729

        assert [
                 %Effects.RewardReputation{team: ^team, faction_id: ^faction, amount: ^reputation},
                 %Effects.RunCreatureScript{creature_entry: ^entry}
               ] = result.effects

        for other <- Air.entries() -- [entry], do: assert(result.match.air[other] == match.air[other])
        again = AlteracValley.quest_rewarded(result.match, guid, quest)
        assert again.match.air[entry].count == goal + 1
        assert [%Effects.RewardReputation{}] = again.effects
        assert again.match.offerings == context.match.offerings
        assert again.match.armor == context.match.armor
      end
    end
  end

  describe "creature_event/3" do
    test "death and respawn require another rescue while retaining donations", context do
      {:close, departure} = AlteracValley.interact(context.match, context.alliance, 13_438, :rescue_commander, 0)
      home = AlteracValley.creature_event(departure.match, 13_438, 1).match
      funded = AlteracValley.quest_rewarded(home, context.alliance, 6_942).match
      reset = AlteracValley.creature_event(funded, 13_438, 0).match
      assert reset.air[13_438] == %Air{count: 1}
      assert AlteracValley.creature_event(reset, 13_438, 1).match == reset
      assert AlteracValley.creature_event(reset, 0, 1).match == reset
      {:close, returning} = AlteracValley.interact(reset, context.alliance, 13_438, :rescue_commander, 0)
      assert returning.match.air[13_438].phase == :returning
    end
  end

  defp commanders do
    [
      {:horde, 13_179, 6_825, 90, 1},
      {:horde, 13_180, 6_826, 60, 2},
      {:horde, 13_181, 6_827, 30, 5},
      {:alliance, 13_438, 6_942, 90, 1},
      {:alliance, 13_439, 6_941, 60, 2},
      {:alliance, 13_437, 6_943, 30, 5}
    ]
  end

  defp active_match(_context) do
    alliance = Unique.integer()
    horde = Unique.integer()
    invited = Unique.integer()

    players = [
      %{guid: alliance, name: "Alliance#{alliance}", team: :alliance},
      %{guid: horde, name: "Horde#{horde}", team: :horde},
      %{guid: invited, name: "Invited#{invited}", team: :alliance}
    ]

    match =
      AlteracValley.new(
        WorldRef.instance(30, Unique.integer()),
        Unique.integer(),
        0,
        %Template{type_id: 1, map_id: 30},
        players,
        0
      ).match

    destination = {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}
    match = AlteracValley.enter(match, alliance, destination).match
    match = AlteracValley.enter(match, horde, destination).match
    %{match: %{match | phase: :active}, alliance: alliance, horde: horde, invited: invited}
  end
end
