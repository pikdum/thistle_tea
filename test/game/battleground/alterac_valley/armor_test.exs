defmodule ThistleTea.Game.Battleground.AlteracValley.ArmorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.AlteracValley
  alias ThistleTea.Game.Battleground.AlteracValley.Armor
  alias ThistleTea.Game.Battleground.AlteracValley.Node
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.WorldRef

  setup [:active_match]

  describe "contribute/3" do
    test "credits each faction's first and repeatable turn-ins without upgrading early", %{match: match} do
      for {guid, team, quests} <- [{1, :alliance, [7_223, 6_781]}, {2, :horde, [7_224, 6_741]}], quest <- quests do
        result = Armor.contribute(match, guid, quest)
        assert result.match.armor[team] == %Armor{scraps: 20}
        assert [%Effects.RewardReputation{team: ^team, amount: 1}] = result.effects
        assert Armor.tier(result.match, team) == 0
      end
    end

    test "rejects wrong-team quests, unentered players, and inactive matches", %{match: match} do
      for {guid, quest} <- [{1, 7_224}, {2, 6_781}, {3, 7_223}, {99, 7_223}, {1, 123}] do
        assert %{match: ^match, effects: []} = Armor.contribute(match, guid, quest)
      end

      for phase <- [:countdown, {:ended, :alliance}] do
        inactive = %{match | phase: phase}
        assert %{match: ^inactive, effects: []} = Armor.contribute(inactive, 1, 7_223)
      end
    end

    test "projects each crate threshold and resets the pile every five hundred scraps", %{match: match} do
      for {guid, team, quest, first_event} <- [{1, :alliance, 6_781, 80}, {2, :horde, 6_741, 81}] do
        Enum.reduce(1..50, match, fn turn, current ->
          result = Armor.contribute(current, guid, quest)
          events = Enum.filter(result.effects, &is_struct(&1, Effects.SetEvent))

          cond do
            rem(turn, 25) == 0 ->
              assert events == for(offset <- [0, 2, 4, 6], do: %Effects.SetEvent{event: first_event + offset, state: 2})

            rem(turn, 5) == 0 ->
              assert events == [%Effects.SetEvent{event: first_event + (div(rem(turn, 25), 5) - 1) * 2, state: 0}]

            true ->
              assert events == []
          end

          assert result.match.armor[team].scraps == turn * 20
          assert result.match.armor[team].tier == 0
          result.match
        end)
      end
    end
  end

  describe "gossip/5 and upgrade/5" do
    test "rechecks reputation, source faction, threshold, and exact next tier", %{match: match} do
      for {guid, team, smith} <- [{1, :alliance, 13_257}, {2, :horde, 13_176}] do
        assert %{options: [%{action: :armor_status}]} = Armor.gossip(match, guid, smith, 42_000)
        funded = put_in(match.armor[team].scraps, 1_520)
        assert %{options: [_status]} = Armor.gossip(funded, guid, smith, 8_999)
        assert Armor.upgrade(funded, guid, smith, 1, 8_999).match == funded

        Enum.reduce(1..3, funded, fn tier, current ->
          assert %{options: [_, %{action: {:upgrade_armor, ^tier}}]} = Armor.gossip(current, guid, smith, 9_000)
          assert Armor.upgrade(current, guid, smith, tier + 1, 9_000).match == current
          upgraded = Armor.upgrade(current, guid, smith, tier, 9_000)
          assert upgraded.match.armor[team] == %Armor{scraps: 1_520, tier: tier}
          assert %Effects.TeamSpell{team: team, spell_id: 28_417 + tier} in upgraded.effects
          assert %Effects.ArmorUpgrade{team: team, tier: tier} in upgraded.effects
          assert Armor.upgrade(upgraded.match, guid, smith, tier, 9_000).effects == []
          upgraded.match
        end)
        |> then(fn champion ->
          assert %{text_id: 6_222, options: []} = Armor.gossip(champion, guid, smith, 42_000)
          assert Armor.upgrade(champion, guid, smith, 4, 42_000).effects == []
        end)
      end

      funded = put_in(match.armor.alliance.scraps, 500)

      for {guid, smith} <- [{1, 13_176}, {1, 123}, {3, 13_257}, {99, 13_257}] do
        assert Armor.gossip(funded, guid, smith, 9_000) == nil
        assert Armor.upgrade(funded, guid, smith, 1, 9_000).effects == []
      end

      assert Armor.upgrade(match, 1, 13_257, 1, 9_000).effects == []
      ended = %{funded | phase: {:ended, :alliance}}
      assert Armor.gossip(ended, 1, 13_257, 9_000) == nil
      assert Armor.upgrade(ended, 1, 13_257, 1, 9_000).effects == []
    end

    test "refreshes controlled defenders and leaves contested or destroyed objectives stopped", %{match: match} do
      {:assaulted, contested} = Node.assault(match.nodes[2], :horde, 0)
      {:assaulted, tower} = Node.assault(match.nodes[7], :horde, 0)
      {:captured, destroyed} = Node.capture(tower, tower.point.revision, 300_000)
      match = %{match | nodes: match.nodes |> Map.put(2, contested) |> Map.put(7, destroyed)}
      match = put_in(match.armor.alliance.scraps, 500)
      upgraded = Armor.upgrade(match, 1, 13_257, 1, 9_000)
      events = for %Effects.SetEvent{event: event, state: state} <- upgraded.effects, into: %{}, do: {event, state}
      assert events[15] == 1
      assert events[16] == 1
      assert events[31] == 1
      refute Map.has_key?(events, 17)
      refute Map.has_key?(events, 22)
      refute Map.has_key?(events, 30)
      refute Map.has_key?(events, 19)
      refute Map.has_key?(events, 18)

      {:handled, defended} =
        AlteracValley.use_game_object(upgraded.match, 1, 100, 178_365, nil, 1, [%{event1: 2, event2: 2}])

      assert %Effects.SetEvent{event: 17, state: 1} in defended.effects
    end
  end

  defp active_match(_context) do
    template = %Template{type_id: 1, map_id: 30}

    players = [
      %{guid: 1, name: "Alliance", team: :alliance},
      %{guid: 2, name: "Horde", team: :horde},
      %{guid: 3, name: "Invited", team: :alliance}
    ]

    match = AlteracValley.new(WorldRef.instance(30, 1), 1, 0, template, players, 0).match
    destination = {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}
    match = Enum.reduce([1, 2], match, &AlteracValley.enter(&2, &1, destination).match)
    %{match: AlteracValley.handle_timer(match, :start, 0).match}
  end
end
