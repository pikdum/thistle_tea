defmodule ThistleTea.Game.Core.Battleground.AlteracValley.OfferingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Offering
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Template
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:active_match]

  describe "quest_rewarded/3" do
    test "combines single and five-item offerings and credits the donating team", context do
      for {guid, team, small, large, faction} <- factions(context) do
        single = AlteracValley.quest_rewarded(context.match, guid, small)
        assert single.match.offerings[team] == %Offering{count: 1}
        assert single.effects == [%Effects.RewardReputation{team: team, faction_id: faction, amount: 1}]
        batch = AlteracValley.quest_rewarded(single.match, guid, large)
        assert batch.match.offerings[team] == %Offering{count: 6}
        assert batch.effects == [%Effects.RewardReputation{team: team, faction_id: faction, amount: 5}]
        assert batch.match.armor == context.match.armor
      end
    end

    test "launches exactly once even when a batch crosses two hundred", context do
      for {guid, team, _small, large, _faction} <- factions(context) do
        funded = put_in(context.match, [Access.key(:offerings), team, Access.key(:count)], 198)
        result = AlteracValley.quest_rewarded(funded, guid, large)
        assert result.match.offerings[team] == %Offering{count: 203, launched?: true}
        assert [%Effects.RewardReputation{}, %Effects.RunCreatureScript{steps: [call, route]}] = result.effects
        assert %ScriptStep{command: :talk} = call
        assert %ScriptStep{command: :start_waypoints, datalong: 5} = route

        if team == :alliance do
          assert call.dataint == 8_732
        else
          assert [%{chat_type: :yell, text: text}] = call.texts
          assert text =~ "Ice Lord"
        end

        again = AlteracValley.quest_rewarded(result.match, guid, large)
        assert [%Effects.RewardReputation{amount: 5}] = again.effects
        assert again.match.offerings[team].launched?
        assert context.match.offerings[team] == %Offering{}
      end
    end

    test "rejects the other faction, unknown quests, absent players, and inactive matches", context do
      for {guid, quest} <- [
            {context.alliance, 7_385},
            {context.horde, 6_881},
            {context.invited, 7_386},
            {Unique.integer(), 6_801},
            {context.alliance, 0}
          ] do
        assert %{match: match, effects: []} = AlteracValley.quest_rewarded(context.match, guid, quest)
        assert match == context.match
      end

      for phase <- [:countdown, {:ended, :horde}] do
        match = %{context.match | phase: phase}
        assert %{match: ^match, effects: []} = AlteracValley.quest_rewarded(match, context.alliance, 7_386)
      end
    end
  end

  describe "gossip/4 and interact/5" do
    test "projects all progress thresholds through both summoners", context do
      for {guid, team, entry, greeting, option, text} <- [
            {context.alliance, :alliance, 13_442, 6_174, 8_757, 6_175},
            {context.horde, :horde, 13_236, 6_093, 8_641, 6_098}
          ],
          {count, progress} <- [{0, 0}, {99, 0}, {100, 1}, {159, 1}, {160, 2}, {199, 2}] do
        match = put_in(context.match, [Access.key(:offerings), team, Access.key(:count)], count)
        expected = option + progress * 2

        assert %{text_id: ^greeting, options: [%{text_id: ^expected, action: :offering_status}]} =
                 AlteracValley.gossip(match, guid, entry, 0)

        reply = %{text_id: text + progress, options: []}

        assert {{:menu, ^reply}, %{match: ^match, effects: []}} =
                 AlteracValley.interact(match, guid, entry, :offering_status, 0)
      end
    end

    test "does not expose another faction's progress or a second launch", context do
      assert AlteracValley.gossip(context.match, context.alliance, 13_236, 0) == nil
      assert AlteracValley.gossip(context.match, context.invited, 13_442, 0) == nil
      assert AlteracValley.gossip(%{context.match | phase: :countdown}, context.alliance, 13_442, 0) == nil
      funded = put_in(context.match, [Access.key(:offerings), :alliance], %Offering{count: 200, launched?: true})
      assert %{options: []} = AlteracValley.gossip(funded, context.alliance, 13_442, 0)
      assert AlteracValley.gossip_entry?(13_442)
      assert AlteracValley.gossip_entry?(13_236)
      assert AlteracValley.gossip_entry?(13_257)
      refute AlteracValley.gossip_entry?(0)
    end
  end

  defp factions(context),
    do: [{context.alliance, :alliance, 6_881, 7_386, 730}, {context.horde, :horde, 6_801, 7_385, 729}]

  defp active_match(_context) do
    alliance = Unique.integer()
    horde = Unique.integer()
    invited = Unique.integer()

    players = [
      %{guid: alliance, name: "Alliance", team: :alliance},
      %{guid: horde, name: "Horde", team: :horde},
      %{guid: invited, name: "Invited", team: :alliance}
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
    match = Enum.reduce([alliance, horde], match, &AlteracValley.enter(&2, &1, destination).match)
    %{match: AlteracValley.handle_timer(match, :start, 0).match, alliance: alliance, horde: horde, invited: invited}
  end
end
