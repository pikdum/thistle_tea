defmodule ThistleTea.Game.Core.Battleground.AlteracValley.GroundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Ground
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Template
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:active_match]

  describe "quest_rewarded/3" do
    test "mine turn-ins contribute ten supplies and reward the contributing faction", context do
      for {team, quest, field, amount} <- [
            {:alliance, 5_892, :irondeep, 2},
            {:alliance, 6_982, :coldtooth, 3},
            {:horde, 5_893, :coldtooth, 2},
            {:horde, 6_985, :irondeep, 3}
          ] do
        result = AlteracValley.quest_rewarded(context.match, context[team], quest)
        ground = result.match.ground[team]
        assert {ground.irondeep, ground.coldtooth} == if(field == :irondeep, do: {10, 0}, else: {0, 10})
        faction = if team == :alliance, do: 730, else: 729
        assert [%Effects.RewardReputation{team: ^team, faction_id: ^faction, amount: ^amount}] = result.effects
        other = if team == :alliance, do: :horde, else: :alliance
        assert result.match.ground[other] == %Ground{}
        assert result.match.armor == context.match.armor
        assert result.match.air == context.match.air
        assert result.match.cavalry == context.match.cavalry
      end
    end

    test "enemy, invited, absent, and inactive players cannot donate or deliver orders", context do
      for quest <- [5_892, 6_982, 6_846],
          {match, guid} <- [
            {context.match, context.horde},
            {context.match, context.invited},
            {context.match, Unique.integer()},
            {%{context.match | phase: :countdown}, context.alliance},
            {%{context.match | phase: {:ended, :horde}}, context.alliance}
          ] do
        assert %{match: ^match, effects: []} = AlteracValley.quest_rewarded(match, guid, quest)
      end
    end

    test "orders launch the assembled commander once even after the quartermaster dies", context do
      for {team, entry, commander, quest, _item} <- teams() do
        match = context.match
        match = put_in(match.ground[team], %Ground{irondeep: 280, coldtooth: 280})
        {:ok, _item, result} = Ground.take_orders(match, context[team], entry, 9_000)
        guid = Unique.integer()
        match = AlteracValley.creature_event(result.match, commander, 3, guid).match
        match = AlteracValley.creature_event(match, entry, 1).match
        match = put_in(match.ground[team].irondeep, 20)
        assert match.ground[team].phase == :assembled
        refute match.ground[team].quartermaster_alive?

        result = AlteracValley.quest_rewarded(match, context[team], quest)
        assert result.match.ground[team].phase == :marching
        assert result.match.ground[team].irondeep == 20

        assert [%Effects.RunCreatureScript{creature_entry: ^commander, creature_guid: ^guid, steps: [%{datalong: 1}]}] =
                 result.effects

        assert %{match: same, effects: []} = AlteracValley.quest_rewarded(result.match, context[team], quest)
        assert same == result.match
      end
    end
  end

  describe "gossip/5" do
    test "either mine threshold unlocks orders at honored while status and vendor remain available", context do
      for {team, entry, _commander, _quest, _item} <- teams(), field <- [:irondeep, :coldtooth] do
        goal = if {team, field} in [{:alliance, :irondeep}, {:horde, :coldtooth}], do: 280, else: 70
        match = context.match
        match = put_in(match.ground[team], struct!(Ground, [{field, goal - 10}]))
        assert AlteracValley.gossip_entry?(entry)

        assert %{text_id: 6_255, vendor?: true, options: [%{action: :ground_status}]} =
                 AlteracValley.gossip(match, context[team], entry, 9_000)

        ready = put_in(match.ground[team], struct!(Ground, [{field, goal}]))

        assert %{options: [%{action: :ground_status}]} = AlteracValley.gossip(ready, context[team], entry, 8_999)

        assert %{options: [%{action: :ground_status}, %{action: :take_ground_orders}]} =
                 AlteracValley.gossip(ready, context[team], entry, 9_000)
      end
    end

    test "status text changes at the reference's strict total thresholds", context do
      for {count, text} <- [{140, 6_733}, {150, 6_732}, {230, 6_732}, {240, 6_731}] do
        match = context.match
        match = put_in(match.ground.alliance.irondeep, count)

        assert {{:menu, %{text_id: ^text, options: []}}, %{match: ^match}} =
                 AlteracValley.interact(match, context.alliance, 12_096, :ground_status, 0)
      end
    end
  end

  describe "take_orders/4" do
    test "assembly consumes both stockpiles once and selects all four armor tiers", context do
      for {team, entry, commander, _quest, item} <- teams(), tier <- 0..3 do
        match = context.match
        match = put_in(match.ground[team], %Ground{irondeep: 290, coldtooth: 80})
        match = put_in(match.armor[team].tier, tier)
        assert {:ok, ^item, result} = Ground.take_orders(match, context[team], entry, 9_000)
        assert result.match.ground[team] == %Ground{phase: :assembled}
        assert [%Effects.RunCreatureScript{creature_entry: ^entry, steps: steps}] = result.effects
        summons = Enum.filter(steps, &(&1.command == :summon_creature))
        assert length(summons) == 11
        assert hd(summons).datalong == commander
        troop = if team == :alliance, do: 13_524 + tier, else: 13_528 + tier
        assert Enum.all?(tl(summons), &(&1.datalong == troop))
        assert summons |> Enum.map(& &1.position) |> Enum.uniq() |> length() == 11
        assert Enum.all?(summons, &(&1.dataint4 == 5 and &1.datalong2 == 10_000))

        assert {:error, :unavailable, %{match: unchanged, effects: []}} =
                 Ground.take_orders(result.match, context[team], entry, 9_000)

        assert unchanged == result.match
      end
    end

    test "invalid and stale requests preserve supplies", context do
      match = context.match
      match = put_in(match.ground.alliance, %Ground{irondeep: 280, coldtooth: 70})

      for {state, guid, entry, standing} <- [
            {match, context.alliance, 12_096, 8_999},
            {match, context.horde, 12_096, 9_000},
            {match, context.invited, 12_096, 9_000},
            {match, context.alliance, 12_097, 9_000},
            {put_in(match.ground.alliance.phase, :marching), context.alliance, 12_096, 9_000},
            {put_in(match.ground.alliance.quartermaster_alive?, false), context.alliance, 12_096, 9_000}
          ] do
        assert {:error, :unavailable, %{match: ^state, effects: []}} = Ground.take_orders(state, guid, entry, standing)
      end
    end

    test "new donations replace lost or expired orders without another assembly", context do
      guid = Unique.integer()
      match = context.match
      match = put_in(match.ground.alliance, %Ground{phase: :assembled, coldtooth: 70, commander_guid: guid})
      assert {:ok, 17_353, result} = Ground.take_orders(match, context.alliance, 12_096, 9_000)
      assert result.effects == []
      assert result.match.ground.alliance == %Ground{phase: :assembled, commander_guid: guid}

      assert [%Effects.RunCreatureScript{creature_guid: ^guid}] =
               AlteracValley.quest_rewarded(result.match, context.alliance, 6_846).effects
    end
  end

  describe "creature_event/4" do
    test "commander deaths cannot rearm a quartermaster or invalidate another deployment", context do
      match = context.match
      match = put_in(match.ground.alliance, %Ground{coldtooth: 70})
      {:ok, _item, result} = Ground.take_orders(match, context.alliance, 12_096, 9_000)
      commander = Unique.integer()
      stale = Unique.integer()
      match = AlteracValley.creature_event(result.match, 13_446, 3, commander).match
      assert AlteracValley.creature_event(match, 13_446, 2, stale).match == match
      dead = AlteracValley.creature_event(match, 13_446, 2, commander).match
      assert dead.ground.alliance.phase == :defeated
      assert AlteracValley.quest_rewarded(dead, context.alliance, 6_846).effects == []
      supplied = put_in(dead.ground.alliance.coldtooth, 70)
      assert {:error, :unavailable, _} = Ground.take_orders(supplied, context.alliance, 12_096, 9_000)
      home = AlteracValley.creature_event(supplied, 12_096, 0).match
      assert home.ground.alliance == %Ground{coldtooth: 70}
      assert {:ok, _item, another} = Ground.take_orders(home, context.alliance, 12_096, 9_000)
      next = Unique.integer()
      match = AlteracValley.creature_event(another.match, 13_446, 3, next).match
      assert AlteracValley.creature_event(match, 13_446, 2, commander).match == match
    end
  end

  defp teams, do: [{:alliance, 12_096, 13_446, 6_846, 17_353}, {:horde, 12_097, 13_449, 6_901, 17_442}]

  defp active_match(_context) do
    alliance = Unique.integer()
    horde = Unique.integer()
    invited = Unique.integer()

    players =
      Enum.map([{alliance, :alliance}, {horde, :horde}, {invited, :alliance}], fn {guid, team} ->
        %{guid: guid, name: "Ground#{guid}", team: team}
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
