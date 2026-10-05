defmodule ThistleTea.Game.Core.Battleground.AlteracValley.AirTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Air
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Template
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:active_match]

  describe "begin_rescue/3" do
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

  describe "gossip/4" do
    test "each supplied fleet offers its own launch at neutral reputation", context do
      for {team, entry, quest, goal, _rep} <- commanders() do
        guid = context[team]
        {:close, departure} = Air.begin_rescue(context.match, guid, entry)
        home = Air.creature_event(departure.match, entry, 1).match
        assert Air.gossip(home, guid, entry, 0) == nil
        supplied = put_in(home.air[entry].count, goal)

        assert %{options: [%{action: :take_air_beacon}, %{action: :launch_air_attack}]} =
                 Air.gossip(supplied, guid, entry, 0)

        assert Air.gossip(supplied, guid, entry, -1) == nil
        assert Air.gossip(supplied, context.invited, entry, 0) == nil
        opponent = context[if(team == :alliance, do: :horde, else: :alliance)]
        assert Air.gossip(supplied, opponent, entry, 0) == nil
        assert Air.gossip(%{supplied | phase: :countdown}, guid, entry, 0) == nil

        assert {:close, launch} = AlteracValley.interact(supplied, guid, entry, :launch_air_attack, 0)
        assert launch.match.air[entry].launched?
        assert launch.match.air[entry].count == goal
        assert [%Effects.RunCreatureScript{creature_entry: ^entry, steps: [%{datalong: 2}]}] = launch.effects
        assert Air.gossip(launch.match, guid, entry, 0) == nil
        assert {:close, %{effects: []}} = Air.interact(launch.match, guid, entry, :launch_air_attack, 0)
        assert AlteracValley.quest_rewarded(launch.match, guid, quest).match.air[entry].count == goal + 1
        assert Enum.all?(Map.delete(launch.match.air, entry), fn {_entry, fleet} -> not fleet.launched? end)
      end
    end
  end

  describe "interact/5" do
    test "rescuing a respawned commander cannot launch the same named attacker again", context do
      match = context.match
      match = put_in(match.air[13_438], %Air{phase: :ready, count: 90})
      {:close, launched} = Air.interact(match, context.alliance, 13_438, :launch_air_attack, 0)
      reset = Air.creature_event(launched.match, 13_438, 0).match
      {:close, rescue_again} = Air.begin_rescue(reset, context.alliance, 13_438)
      home = Air.creature_event(rescue_again.match, 13_438, 1).match
      assert home.air[13_438] == %Air{phase: :ready, count: 90, launched?: true}
      assert {:close, %{effects: []}} = Air.interact(home, context.alliance, 13_438, :launch_air_attack, 0)
    end
  end

  describe "take_beacon/4" do
    test "each fleet resets supplies once and can grant another beacon after resupplying", context do
      items = %{
        13_179 => 17_324,
        13_180 => 17_325,
        13_181 => 17_323,
        13_438 => 17_506,
        13_439 => 17_507,
        13_437 => 17_505
      }

      for {team, entry, _quest, goal, _rep} <- commanders() do
        guid = context[team]
        match = context.match
        match = put_in(match.air[entry], %Air{phase: :ready, count: goal + 10})
        item = Map.fetch!(items, entry)
        assert {:ok, ^item, result} = Air.take_beacon(match, guid, entry, 0)
        assert result.effects == []
        assert result.match.air[entry].count == 0
        assert {:error, :unavailable, %{match: retained}} = Air.take_beacon(result.match, guid, entry, 0)
        assert retained == result.match
        restocked = put_in(retained.air[entry].count, goal)

        assert %{options: [%{action: :take_air_beacon}, %{action: :launch_air_attack}]} =
                 Air.gossip(restocked, guid, entry, 0)

        assert {:ok, ^item, again} = Air.take_beacon(restocked, guid, entry, 0)
        assert again.match.air[entry].count == 0
        assert Map.delete(again.match.air, entry) == Map.delete(context.match.air, entry)
      end
    end

    test "unfunded, enemy, offline and low reputation requests preserve stockpiles", context do
      match = context.match
      match = put_in(match.air[13_179], %Air{phase: :ready, count: 90})

      for {candidate, guid, standing} <- [
            {match, context.alliance, 0},
            {match, context.invited, 0},
            {match, context.horde, -1},
            {%{match | phase: :countdown}, context.horde, 0},
            {put_in(match.air[13_179].phase, :returning), context.horde, 0},
            {put_in(match.air[13_179].count, 89), context.horde, 0},
            {put_in(match.air[13_179].launched?, true), context.horde, 0}
          ] do
        assert {:error, :unavailable, %{match: ^candidate, effects: []}} =
                 Air.take_beacon(candidate, guid, 13_179, standing)
      end
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
