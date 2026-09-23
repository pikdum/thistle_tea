defmodule ThistleTea.Game.Battleground.ArathiBasinTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.ArathiBasin
  alias ThistleTea.Game.Battleground.ControlPoint
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.WorldRef

  setup [:active_match]

  describe "use_game_object/7" do
    test "claims, captures, defends, and rejects stale capture and banner timers", %{match: match} do
      claim = use_node(match, 0, 1, 0)
      assert claim.match.players[1].bases_assaulted == 1
      assert %Effects.QuestKillCredit{guid: 1, entry: 15_001} in claim.effects
      assert %Effects.SetEvent{event: 0, state: nil} in claim.effects
      assert Map.new(ArathiBasin.world_states(claim.match))[1_769] == 1
      assert Map.new(ArathiBasin.world_states(claim.match))[1_779] == 0
      assert {{:capture, 0, 1}, 60_000} in claim.timers

      banner = ArathiBasin.handle_timer(claim.match, {:banner, 0, 1}, 1_000)
      assert banner.effects == [%Effects.SetEvent{event: 0, state: 1}]
      owned = ArathiBasin.handle_timer(claim.match, {:capture, 0, 1}, 60_000)
      assert ControlPoint.controlled_by(owned.match.nodes[0]) == :alliance
      assert {{:banner, 0, 2}, 5_000} in owned.timers

      assault = use_node(owned.match, 0, 2, 70_000)
      assert assault.match.players[2].bases_assaulted == 1
      assert ControlPoint.controlled_by(assault.match.nodes[0]) == nil
      defense = use_node(assault.match, 0, 1, 80_000)
      assert defense.match.players[1].bases_defended == 1
      assert ControlPoint.controlled_by(defense.match.nodes[0]) == :alliance
      assert ArathiBasin.handle_timer(defense.match, {:banner, 0, 3}, 81_000).effects == []
      stale = ArathiBasin.handle_timer(defense.match, {:capture, 0, 3}, 130_000)
      assert ControlPoint.controlled_by(stale.match.nodes[0]) == :alliance
      refute Enum.any?(stale.effects, &match?(%Effects.SetEvent{}, &1))
      assert [%{fields: [1, 1]}, %{fields: [1, 0]}] = ArathiBasin.scoreboard(defense.match)
    end

    test "counter-assaulting a neutral claim waits a new minute", %{match: match} do
      claim = use_node(match, 0, 1, 0)
      counter = use_node(claim.match, 0, 2, 30_000)
      stale = ArathiBasin.handle_timer(counter.match, {:capture, 0, 1}, 60_000)
      assert ControlPoint.controlled_by(stale.match.nodes[0]) == nil
      owned = ArathiBasin.handle_timer(stale.match, {:capture, 0, 2}, 90_000)
      assert ControlPoint.controlled_by(owned.match.nodes[0]) == :horde
      assert owned.match.players[2].bases_defended == 0
    end

    test "rejects stale object states, uninvited players, and friendly flags", %{match: match} do
      claimed = use_node(match, 0, 1, 0).match
      assert use_node(claimed, 0, 2, 1_000, 0).match == claimed
      assert use_node(claimed, 0, 99, 1_000).match == claimed
      assert use_node(claimed, 0, 1, 1_000).effects == []
      countdown = %{match | phase: :countdown}
      assert use_node(countdown, 0, 1, 0).match == countdown
      ended = %{match | phase: {:ended, :alliance}}
      assert use_node(ended, 0, 2, 0).match == ended
    end

    test "awards four and five base quest spells only when control is established", %{match: match} do
      match = own_nodes(match, 0..2, :alliance)
      claim = use_node(match, 3, 1, 0)
      refute Enum.any?(claim.effects, &match?(%Effects.TeamSpell{}, &1))
      four = ArathiBasin.handle_timer(claim.match, {:capture, 3, 1}, 60_000)
      assert %Effects.TeamSpell{team: :alliance, spell_id: 24_061} in four.effects
      claim = use_node(four.match, 4, 1, 60_000)
      five = ArathiBasin.handle_timer(claim.match, {:capture, 4, 1}, 120_000)
      assert %Effects.TeamSpell{team: :alliance, spell_id: 24_061} in five.effects
      assert %Effects.TeamSpell{team: :alliance, spell_id: 24_064} in five.effects
    end
  end

  describe "handle_timer/3" do
    test "uses the resource interval for each base count", %{match: match} do
      intervals = [{1, 12_000, 10}, {2, 9_000, 10}, {3, 6_000, 10}, {4, 3_000, 10}, {5, 1_000, 30}]

      for {count, interval, points} <- intervals do
        owned = own_nodes(match, 0..(count - 1), :alliance)
        before = ArathiBasin.handle_timer(owned, :resources, interval - 1)
        assert before.match.team_scores.alliance == 0
        scored = ArathiBasin.handle_timer(before.match, :resources, interval)
        assert scored.match.team_scores == %{alliance: points, horde: 0}
      end
    end

    test "pauses an assaulted base and resumes its retained resource progress on defense", %{match: match} do
      owned = own_nodes(match, [0], :alliance)
      assault = use_node(owned, 0, 2, 11_000)
      paused = ArathiBasin.handle_timer(assault.match, :resources, 21_000)
      assert paused.match.team_scores.alliance == 0
      defense = use_node(paused.match, 0, 1, 21_000)
      resumed = ArathiBasin.handle_timer(defense.match, :resources, 22_000)
      assert resumed.match.team_scores.alliance == 10
    end

    test "retains resource progress as the controlled base count changes", %{match: match} do
      owned = own_nodes(match, [0, 1], :alliance)
      partial = ArathiBasin.handle_timer(owned, :resources, 8_000)
      assault = use_node(partial.match, 1, 2, 8_000)
      before = ArathiBasin.handle_timer(assault.match, :resources, 11_999)
      assert before.match.team_scores.alliance == 0
      assert ArathiBasin.handle_timer(before.match, :resources, 12_000).match.team_scores.alliance == 10
    end

    test "scores both teams and credits honor and reputation at independent thresholds", %{match: match} do
      match = match |> own_nodes([0, 1], :alliance) |> own_nodes([2, 3], :horde)
      result = ArathiBasin.handle_timer(match, :resources, 297_000)
      assert result.match.team_scores == %{alliance: 330, horde: 330}
      assert %Effects.RewardHonor{guids: [1], amount: 198} in result.effects
      assert %Effects.RewardHonor{guids: [2], amount: 198} in result.effects
      assert %Effects.RewardReputation{team: :alliance, faction_id: 509, amount: 10} in result.effects
      assert %Effects.RewardReputation{team: :horde, faction_id: 510, amount: 10} in result.effects
      assert result.match.reputation_progress == %{alliance: 130, horde: 130}
    end

    test "finishes at 2000, rewards once, and sends the final scoreboard and exit timer", %{match: match} do
      match = own_nodes(match, 0..4, :alliance)
      warning = ArathiBasin.handle_timer(match, :resources, 61_000)
      assert warning.match.team_scores.alliance == 1_830
      assert %Effects.Announce{broadcast_text_id: 10_598, audience: :neutral} in warning.effects
      ended = ArathiBasin.handle_timer(warning.match, :resources, 67_000)
      assert ended.match.phase == {:ended, :alliance}
      assert ended.match.team_scores == %{alliance: 2_000, horde: 0}
      assert ended.match.players[1].bonus_honor == 1_386
      assert ended.timers == [auto_leave: 120_000]
      assert Enum.any?(ended.effects, &match?(%Effects.RewardPlayers{winner: :alliance}, &1))
      assert Enum.any?(ended.effects, &match?(%Effects.Scoreboard{ended?: true, winner: :alliance}, &1))
      assert ArathiBasin.handle_timer(ended.match, :resources, 68_000).effects == []
      assert ArathiBasin.handle_timer(ended.match, {:capture, 0, 1}, 68_000).effects == []
      assert ArathiBasin.handle_timer(ended.match, {:banner, 0, 1}, 68_000).effects == []
      exit = ArathiBasin.handle_timer(ended.match, :auto_leave, 187_000)
      assert [%Effects.ExitPlayers{destinations: destinations}] = exit.effects
      assert map_size(destinations) == 2
    end

    test "applies weekend resource thresholds and double victory honor", %{match: match} do
      match = %{own_nodes(match, 0..4, :alliance) | weekend?: true}
      ended = ArathiBasin.handle_timer(match, :resources, 67_000)
      assert ended.match.players[1].bonus_honor == 2_376
      assert %Effects.RewardReputation{team: :alliance, faction_id: 509, amount: 130} in ended.effects
    end

    test "departure removes queued resurrection and reconnect preserves objective scores", %{match: match} do
      match = use_node(match, 0, 1, 0).match
      queued = ArathiBasin.queue_resurrection(match, 1).match
      disconnected = ArathiBasin.disconnect(queued, 1, nil, nil).match
      reconnected = ArathiBasin.reconnect(disconnected, 1).match
      assert reconnected.players[1].bases_assaulted == 1
      left = ArathiBasin.leave(reconnected, 1, nil, nil).match
      assert ArathiBasin.handle_timer(left, :resurrection_wave, 30_000).effects == []
    end
  end

  describe "graveyard/3" do
    test "chooses the closest controlled node, excluding contested and enemy nodes", %{match: match} do
      match = match |> own_nodes([0, 1], :alliance) |> own_nodes([2], :horde)
      assert ArathiBasin.graveyard(match, :alliance, {9.0, 0.0, 0.0}) == {10.0, 0.0, 0.0, 0.0}
      contested = use_node(match, 1, 2, 0).match
      assert ArathiBasin.graveyard(contested, :alliance, {9.0, 0.0, 0.0}) == {0.0, 0.0, 0.0, 0.0}
      none = use_node(contested, 0, 2, 0).match
      assert ArathiBasin.graveyard(none, :alliance, {9.0, 0.0, 0.0}) == match.template.alliance_graveyard

      assert ArathiBasin.graveyard(%{match | phase: :countdown}, :alliance, {9.0, 0.0, 0.0}) ==
               match.template.alliance_start
    end
  end

  describe "world_states/1" do
    test "initializes every node icon and state for joining clients", %{match: match} do
      states = Map.new(ArathiBasin.world_states(match))
      assert map_size(states) == 32
      assert states[1_780] == 2_000
      assert states[1_955] == 1_800
      assert Enum.all?([1_842, 1_846, 1_845, 1_844, 1_843], &(states[&1] == 1))
      assert Enum.all?([1_767, 1_782, 1_772, 1_792, 1_787], &(states[&1] == 0))
    end
  end

  defp active_match(_context) do
    template = %Template{
      alliance_start: {-100.0, 0.0, 0.0, 0.0},
      horde_start: {100.0, 0.0, 0.0, 0.0},
      alliance_graveyard: {-50.0, 0.0, 0.0, 0.0},
      horde_graveyard: {50.0, 0.0, 0.0, 0.0},
      node_graveyards: Map.new(0..4, &{&1, {&1 * 10.0, 0.0, 0.0, 0.0}})
    }

    players = [%{guid: 1, name: "Alliance", team: :alliance}, %{guid: 2, name: "Horde", team: :horde}]
    match = ArathiBasin.new(WorldRef.instance(529, 1), 1, 5, template, players, 0).match
    destination = {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}
    match = Enum.reduce([1, 2], match, &ArathiBasin.enter(&2, &1, destination).match)
    %{match: ArathiBasin.handle_timer(match, :start, 0).match}
  end

  defp use_node(match, node, guid, now, state \\ nil) do
    state = state || ControlPoint.state(match.nodes[node])

    {:handled, result} =
      ArathiBasin.use_game_object(match, guid, 100 + node, 180_059, nil, now, [%{event1: node, event2: state}])

    result
  end

  defp own_nodes(match, nodes, team) do
    %{match | nodes: Enum.reduce(nodes, match.nodes, &Map.put(&2, &1, %ControlPoint{owner: team}))}
  end
end
