defmodule ThistleTea.Game.Battleground.AlteracValleyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.AlteracValley
  alias ThistleTea.Game.Battleground.AlteracValley.Node
  alias ThistleTea.Game.Battleground.CreatureDefeat
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.Network.Message.MsgPvpLogData
  alias ThistleTea.Game.WorldRef

  setup [:active_match]

  describe "scoreboard/1" do
    test "encodes seven ordered objective fields for build 5875", %{match: match} do
      match = put_in(match.players[1].mines_captured, 2)
      match = put_in(match.players[1].leaders_killed, 3)
      match = put_in(match.players[1].secondary_objectives, 4)
      [player | _] = AlteracValley.scoreboard(match)
      message = %MsgPvpLogData{players: [player]}

      assert <<0, 1::little-size(32), 1::little-size(64), _scores::binary-size(20), 7::little-size(32),
               0::little-size(32), 0::little-size(32), 0::little-size(32), 0::little-size(32), 2::little-size(32),
               3::little-size(32), 4::little-size(32)>> = MsgPvpLogData.to_binary(message)
    end
  end

  describe "use_game_object/7" do
    test "stops graveyard respawns during assault and restores them on defense", %{match: match} do
      attacked = use_node(match, 2, 2, 0)
      assert %Effects.StopEventRespawns{event: 17} in attacked.effects
      assert %Effects.SetEvent{event: 2, state: nil} in attacked.effects
      assert {{:capture, 2, 1}, 300_000} in attacked.timers
      assert {{:banner, 2, 1}, 1_000} in attacked.timers
      assert attacked.match.players[2].graveyards_assaulted == 1
      assert [%Effects.QuestKillCredit{guid: 2, entry: 13_756}] == quest_credits(attacked)

      defended = use_node(attacked.match, 2, 1, 1_000)
      assert %Effects.SetEvent{event: 17, state: 0} in defended.effects
      assert {{:banner, 2, 2}, 5_000} in defended.timers
      assert defended.match.players[1].graveyards_defended == 1
      assert quest_credits(defended) == []
      assert AlteracValley.handle_timer(defended.match, {:banner, 2, 1}, 2_000).effects == []
      assert AlteracValley.handle_timer(defended.match, {:capture, 2, 1}, 300_000).match == defended.match

      assert [%{fields: [0, 1, 0, 0, 0, 0, 0]}, %{fields: [1, 0, 0, 0, 0, 0, 0]}, %{fields: [0, 0, 0, 0, 0, 0, 0]}] =
               AlteracValley.scoreboard(defended.match)
    end

    test "destroys a tower once, swaps both guard events, and awards the capturing team", %{match: match} do
      attacked = use_node(match, 11, 1, 0)
      assert %Effects.StopEventRespawns{event: 26} in attacked.effects
      assert %Effects.StopEventRespawns{event: 34} in attacked.effects
      assert [%Effects.QuestKillCredit{guid: 1, entry: 13_778}] == quest_credits(attacked)
      captured = AlteracValley.handle_timer(attacked.match, {:capture, 11, 1}, 300_000)
      assert captured.match.nodes[11].destroyed?
      assert captured.match.players[1].towers_assaulted == 1
      assert captured.match.players[1].bonus_honor == 396
      assert captured.match.players[2].bonus_honor == 0
      assert %Effects.SetEvent{event: 26, state: 1} in captured.effects
      assert %Effects.SetEvent{event: 34, state: 0} in captured.effects
      assert %Effects.RewardReputation{team: :alliance, faction_id: 730, amount: 12} in captured.effects
      assert quest_credits(captured) == []
      assert AlteracValley.handle_timer(captured.match, {:capture, 11, 1}, 400_000).effects == []
      assert use_node(captured.match, 11, 2, 400_000).match == captured.match
    end

    test "requires an enemy graveyard for assault quest credit", %{match: match} do
      neutral = use_node(match, 3, 1, 0)
      assert quest_credits(neutral) == []
      captured = AlteracValley.handle_timer(neutral.match, {:capture, 3, 1}, 300_000)
      assert quest_credits(captured) == []
      attacked = use_node(captured.match, 3, 2, 301_000)
      assert [%Effects.QuestKillCredit{guid: 2, entry: 13_756}] == quest_credits(attacked)
    end

    test "rejects preparation, absent players, stale banners, and unrelated objects", %{match: match} do
      assert use_node(%{match | phase: :countdown}, 2, 2, 0).effects == []
      assert use_node(match, 2, 3, 0).effects == []
      assert use_node(match, 2, 99, 0).effects == []

      assert {:handled, %{match: ^match, effects: []}} =
               AlteracValley.use_game_object(match, 2, 1, 178_365, nil, 0, [%{event1: 2, event2: 3}])

      assert {:unhandled, %{match: ^match}} = AlteracValley.use_game_object(match, 1, 1, 123, nil, 0, [])
    end
  end

  describe "creature_died/3" do
    test "captures mines, rejects duplicates and obsolete bosses, and gates supply loot", %{match: match} do
      refute AlteracValley.supply_allowed?(match, 1, 178_785)
      neutral = defeat(46, 1, 9, 2)
      captured = AlteracValley.creature_died(match, neutral, 1_000)
      assert captured.match.mines[0].owner == :alliance
      assert captured.match.players[1].mines_captured == 1
      assert captured.match.players[2].mines_captured == 0
      assert %Effects.SetEvent{event: 46, state: 0} in captured.effects
      assert %Effects.SetEvent{event: 50, state: 0} in captured.effects
      assert %Effects.QuestKillCredit{guid: 1, entry: 13_796} in captured.effects
      assert {{:mine_reclaim, 0, 1}, 1_200_000} in captured.timers
      assert AlteracValley.supply_allowed?(captured.match, 1, 178_785)
      refute AlteracValley.supply_allowed?(captured.match, 2, 178_785)
      refute AlteracValley.supply_allowed?(captured.match, 3, 178_785)
      refute AlteracValley.supply_allowed?(captured.match, 1, 178_784)
      assert AlteracValley.creature_died(captured.match, neutral, 2_000).effects == []
      assert AlteracValley.creature_died(captured.match, defeat(46, 2, 10, 2), 2_000).effects == []
      assert AlteracValley.creature_died(captured.match, defeat(46, 1, 10, 0), 2_000).effects == []

      recaptured = AlteracValley.creature_died(captured.match, defeat(46, 2, 10, 0), 3_000)
      assert recaptured.match.mines[0].owner == :horde
      assert recaptured.match.players[2].mines_captured == 1
      assert AlteracValley.handle_timer(recaptured.match, {:mine_reclaim, 0, 1}, 1_201_000).effects == []
      reclaimed = AlteracValley.handle_timer(recaptured.match, {:mine_reclaim, 0, 2}, 1_203_000)
      assert reclaimed.match.mines[0].owner == nil
      assert reclaimed.match.players[2].mines_captured == 1
      assert %Effects.SetEvent{event: 46, state: 2} in reclaimed.effects
      refute AlteracValley.supply_allowed?(reclaimed.match, 2, 178_785)
    end

    test "captain death stops buffs and respawns and awards only once", %{match: match} do
      before = AlteracValley.handle_timer(match, {:captain_buff, :horde}, 120_000)
      assert %Effects.TeamSpell{team: :horde, spell_id: 22_751} in before.effects
      killed = AlteracValley.creature_died(match, defeat(49, 1), 120_001)
      assert killed.match.players[1].bonus_honor == 594
      assert killed.match.players[1].leaders_killed == 1
      assert %Effects.StopEventRespawns{event: 49} in killed.effects
      assert %Effects.SetEvent{event: 64, state: 0} in killed.effects
      assert AlteracValley.handle_timer(killed.match, {:captain_buff, :horde}, 300_000).effects == []
      assert AlteracValley.creature_died(killed.match, defeat(49, 1, 2), 300_000).effects == []

      assert Enum.any?(
               AlteracValley.handle_timer(killed.match, {:captain_buff, :alliance}, 300_000).effects,
               &match?(%Effects.TeamSpell{spell_id: 23_693}, &1)
             )
    end

    test "commanders are one-time objectives while lieutenant incarnations may respawn", %{match: match} do
      commander = AlteracValley.creature_died(match, defeat(57, 1), 0)
      assert commander.match.players[1].bonus_honor == 198
      assert commander.match.players[1].leaders_killed == 1
      assert %Effects.QuestKillCredit{guid: 1, entry: 13_154} in commander.effects
      assert AlteracValley.creature_died(commander.match, defeat(57, 1, 2), 1).effects == []

      lieutenant = AlteracValley.creature_died(commander.match, defeat(69, 1), 2)
      assert lieutenant.match.players[1].bonus_honor == 396
      assert AlteracValley.creature_died(lieutenant.match, defeat(69, 1), 3).effects == []
      respawn = AlteracValley.creature_died(lieutenant.match, defeat(69, 1, 2), 4)
      assert respawn.match.players[1].bonus_honor == 594
      assert respawn.match.players[1].leaders_killed == 3
    end

    test "enemy general death ends the match and includes survival rewards in the final scoreboard", %{match: match} do
      assert AlteracValley.creature_died(match, defeat(61, 1), 0).effects == []
      assert AlteracValley.creature_died(match, defeat(62, 3), 0).effects == []
      assert AlteracValley.creature_died(%{match | phase: :countdown}, defeat(62, 1), 0).effects == []
      match = AlteracValley.queue_resurrection(match, 2).match
      victory = AlteracValley.creature_died(match, defeat(62, 1), 3_600_000)
      assert victory.match.phase == {:ended, :alliance}
      assert victory.match.resurrection_queue == MapSet.new()
      assert victory.match.players[1].bonus_honor == 198 * (6 + 4 * 3 + 3 + 2)
      assert victory.match.players[2].bonus_honor == 198 * (4 * 3 + 3 + 2)
      assert %Effects.TeamSpell{team: :alliance, spell_id: 23_658} in victory.effects

      assert [%Effects.RewardPlayers{winner: :alliance, players: rewarded}] =
               Enum.filter(victory.effects, &is_struct(&1, Effects.RewardPlayers))

      assert Enum.map(rewarded, & &1.guid) |> Enum.sort() == [1, 2]

      assert [%Effects.Scoreboard{ended?: true, winner: :alliance, players: scores}] =
               Enum.filter(victory.effects, &is_struct(&1, Effects.Scoreboard))

      assert hd(scores).bonus_honor == victory.match.players[1].bonus_honor
      assert victory.timers == [auto_leave: 120_000]
      assert AlteracValley.creature_died(victory.match, defeat(61, 2), 3_600_001).effects == []
      assert AlteracValley.handle_timer(victory.match, {:captain_buff, :alliance}, 3_600_001).effects == []

      assert [%Effects.ExitPlayers{destinations: destinations}] =
               AlteracValley.handle_timer(victory.match, :auto_leave, 3_720_000).effects

      assert Map.keys(destinations) == [1, 2]
    end
  end

  describe "graveyard/3" do
    test "chooses the nearest cave or uncontested friendly graveyard by horizontal distance", %{match: match} do
      assert AlteracValley.graveyard(match, :alliance, {201.0, 0.0, 0.0}) == {200.0, 0.0, 500.0, 0.0}
      attacked = use_node(match, 2, 2, 0).match
      assert AlteracValley.graveyard(attacked, :alliance, {201.0, 0.0, 0.0}) == {100.0, 0.0, 500.0, 0.0}
      assert AlteracValley.graveyard(match, :alliance, {-99.0, 0.0, 0.0}) == {-100.0, 0.0, 0.0, 0.0}

      assert AlteracValley.graveyard(%{match | phase: :countdown}, :alliance, {201.0, 0.0, 0.0}) ==
               {-100.0, 0.0, 0.0, 0.0}
    end
  end

  describe "world_states/1" do
    test "projects one icon per objective without reinforcement counters", %{match: match} do
      states = AlteracValley.world_states(match)
      assert length(states) == 67
      assert Enum.count(states, fn {_field, value} -> value == 1 end) == 17
      assert length(Enum.uniq_by(states, &elem(&1, 0))) == 67
      refute Enum.any?(states, fn {field, _value} -> field in [3_127, 3_128, 3_133, 3_134] end)
    end
  end

  defp active_match(_context) do
    template = %Template{
      type_id: 1,
      map_id: 30,
      alliance_graveyard: {-100.0, 0.0, 0.0, 0.0},
      horde_graveyard: {700.0, 0.0, 0.0, 0.0},
      node_graveyards: Map.new(0..6, &{&1, {&1 * 100.0, 0.0, 500.0, 0.0}})
    }

    players = [
      %{guid: 1, name: "Alliance", team: :alliance},
      %{guid: 2, name: "Horde", team: :horde},
      %{guid: 3, name: "Invited", team: :alliance}
    ]

    match = AlteracValley.new(WorldRef.instance(30, 1), 1, 0, template, players, 0).match
    destination = {WorldRef.open(0), {1.0, 2.0, 3.0, 0.0}}
    match = Enum.reduce([1, 2], match, &AlteracValley.enter(&2, &1, destination).match)
    %{match: AlteracValley.handle_timer(match, :start, 0).match}
  end

  defp quest_credits(result), do: Enum.filter(result.effects, &is_struct(&1, Effects.QuestKillCredit))

  defp use_node(match, node, guid, now) do
    bindings = [%{event1: node, event2: Node.event_state(match.nodes[node])}]
    {:handled, result} = AlteracValley.use_game_object(match, guid, 1, 178_365, nil, now, bindings)
    result
  end

  defp defeat(event, killer, incarnation \\ 1, state \\ 0) do
    %CreatureDefeat{
      victim_guid: 100 + event,
      entry: 1,
      db_guid: event,
      incarnation_id: incarnation,
      killer_guid: killer,
      bindings: [%{event1: event, event2: state}]
    }
  end
end
