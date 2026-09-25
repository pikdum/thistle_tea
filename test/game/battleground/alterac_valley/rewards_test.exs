defmodule ThistleTea.Game.Battleground.AlteracValley.RewardsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.AlteracValley
  alias ThistleTea.Game.Battleground.AlteracValley.Node
  alias ThistleTea.Game.Battleground.AlteracValley.Rewards
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.WorldRef

  setup [:match]

  describe "objective/5" do
    test "short matches scale general honor but preserve objective reputation and captain honor", %{match: match} do
      {quick, effects} = Rewards.objective(match, :alliance, :general, 0)
      {full, _effects} = Rewards.objective(match, :alliance, :general, 3_600_000)
      {later, _effects} = Rewards.objective(match, :alliance, :general, 7_200_000)
      {captain, _effects} = Rewards.objective(match, :alliance, :captain, 0)
      assert quick.players[1].bonus_honor == 19
      assert full.players[1].bonus_honor == 1_188
      assert later.players[1].bonus_honor == 1_188
      assert captain.players[1].bonus_honor == 594
      assert %Effects.RewardReputation{team: :alliance, faction_id: 730, amount: 350} in effects
      assert quick.players[3].bonus_honor == 0

      {_match, weekend} = Rewards.objective(%{match | weekend?: true}, :alliance, :general, 0)
      assert %Effects.RewardReputation{team: :alliance, faction_id: 730, amount: 525} in weekend
    end
  end

  describe "finish/3" do
    test "excludes contested towers and dead captains from survival rewards", %{match: match} do
      {intact, _effects} = Rewards.finish(match, :alliance, 3_600_000)
      {:assaulted, tower} = Node.assault(match.nodes[7], :horde, 0)
      match = %{match | nodes: Map.put(match.nodes, 7, tower), defeated_events: MapSet.new([48])}
      {damaged, _effects} = Rewards.finish(match, :alliance, 3_600_000)
      assert intact.players[1].bonus_honor - damaged.players[1].bonus_honor == 1_188
      assert intact.players[2].bonus_honor == damaged.players[2].bonus_honor

      {weekend, _effects} = Rewards.finish(%{match | weekend?: true}, :alliance, 3_600_000)
      assert weekend.players[1].bonus_honor - damaged.players[1].bonus_honor == 1_980
      assert weekend.players[2].bonus_honor - damaged.players[2].bonus_honor == 1_584
    end
  end

  defp match(_context) do
    players = [
      %{guid: 1, name: "Alliance", team: :alliance, status: :inside},
      %{guid: 2, name: "Horde", team: :horde, status: :inside},
      %{guid: 3, name: "Offline", team: :alliance, status: :offline}
    ]

    match = AlteracValley.new(WorldRef.instance(30, 1), 1, 0, %Template{}, players, 0).match
    %{match: AlteracValley.handle_timer(match, :start, 0).match}
  end
end
