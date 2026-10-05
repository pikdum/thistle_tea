defmodule ThistleTea.Game.Core.Battleground.AlteracValley.CavalryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Cavalry
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Template
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:active_match]

  describe "quest_rewarded/3" do
    test "each team counts hides and mounts independently and projects every fifth mount", context do
      match = context.match

      for {team, hide, tame, _entry, index, faction} <- teams() do
        player = context[team]
        hide_result = AlteracValley.quest_rewarded(context.match, player, hide)
        assert hide_result.match.cavalry[team] == %Cavalry{hides: 1}
        assert [%Effects.RewardReputation{team: ^team, faction_id: ^faction, amount: 1}] = hide_result.effects

        for count <- [5, 10, 15, 20] do
          match = put_in(match.cavalry[team].mounts, count - 1)
          result = AlteracValley.quest_rewarded(match, player, tame)
          assert result.match.cavalry[team].mounts == count
          event = 90 + index + div(count - 5, 5) * 2
          assert [%Effects.RewardReputation{}, %Effects.SetEvent{event: ^event, state: 0}] = result.effects
          other = if team == :alliance, do: :horde, else: :alliance
          assert result.match.cavalry[other] == %Cavalry{}
          assert result.match.armor == context.match.armor
          assert result.match.offerings == context.match.offerings
          assert result.match.air == context.match.air
        end
      end
    end

    test "enemy, invited, absent and inactive contributions cannot supply a team", context do
      for {match, guid, quest} <- [
            {context.match, context.alliance, 7_001},
            {context.match, context.horde, 7_026},
            {context.match, context.invited, 7_027},
            {context.match, Unique.integer(), 7_026},
            {%{context.match | phase: :countdown}, context.alliance, 7_026},
            {%{context.match | phase: {:ended, :horde}}, context.horde, 7_001}
          ] do
        assert %{match: ^match, effects: []} = AlteracValley.quest_rewarded(match, guid, quest)
      end
    end
  end

  describe "interact/5" do
    test "launch requires both supplies and honored reputation, consumes stock once and empties stables", context do
      match = context.match

      for {team, _hide, _tame, entry, index, _faction} <- teams() do
        player = context[team]
        match = put_in(match.cavalry[team], %Cavalry{hides: 26, mounts: 27})
        assert AlteracValley.gossip_entry?(entry)
        assert %{options: [%{action: :launch_cavalry_attack}]} = AlteracValley.gossip(match, player, entry, 9_000)

        for invalid <- [
              put_in(match.cavalry[team].hides, 24),
              put_in(match.cavalry[team].mounts, 24),
              put_in(match.cavalry[team].phase, :dead)
            ] do
          assert {:close, %{match: ^invalid, effects: []}} =
                   AlteracValley.interact(invalid, player, entry, :launch_cavalry_attack, 9_000)
        end

        assert {:close, %{match: ^match, effects: []}} =
                 AlteracValley.interact(match, player, entry, :launch_cavalry_attack, 8_999)

        assert {:close, result} = AlteracValley.interact(match, player, entry, :launch_cavalry_attack, 9_000)
        assert result.match.cavalry[team] == %Cavalry{phase: :marching}

        assert Enum.take(result.effects, 4) ==
                 Enum.map([90, 92, 94, 96], &%Effects.SetEvent{event: &1 + index, state: 2})

        assert %Effects.RunCreatureScript{creature_entry: ^entry, steps: [%{datalong: 1}]} = List.last(result.effects)

        assert {:close, %{effects: []}} =
                 AlteracValley.interact(result.match, player, entry, :launch_cavalry_attack, 9_000)
      end
    end
  end

  describe "creature_event/3" do
    test "donations survive a commander death and respawn and can fund another sortie", context do
      match = context.match
      match = put_in(match.cavalry.alliance, %Cavalry{hides: 25, mounts: 25})
      {:close, launch} = AlteracValley.interact(match, context.alliance, 13_577, :launch_cavalry_attack, 9_000)
      launched = launch.match
      supplied = put_in(launched.cavalry.alliance, %Cavalry{phase: :marching, hides: 25, mounts: 25})
      assert AlteracValley.gossip(supplied, context.alliance, 13_577, 9_000) == nil
      dead = AlteracValley.creature_event(supplied, 13_577, 1).match
      assert dead.cavalry.alliance.phase == :dead
      home = AlteracValley.creature_event(dead, 13_577, 0).match
      assert home.cavalry.alliance == %Cavalry{hides: 25, mounts: 25}

      assert {:close, %{effects: [_ | _]}} =
               AlteracValley.interact(home, context.alliance, 13_577, :launch_cavalry_attack, 9_000)

      assert AlteracValley.creature_event(home, Unique.integer(), 0).match == home
    end
  end

  defp teams, do: [{:alliance, 7_026, 7_027, 13_577, 0, 730}, {:horde, 7_002, 7_001, 13_441, 1, 729}]

  defp active_match(_context) do
    alliance = Unique.integer()
    horde = Unique.integer()
    invited = Unique.integer()

    players =
      Enum.map([{alliance, :alliance}, {horde, :horde}, {invited, :alliance}], fn {guid, team} ->
        %{guid: guid, name: "Cavalry#{guid}", team: team}
      end)

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
