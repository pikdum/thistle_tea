defmodule ThistleTea.Game.Battleground.WarsongGulchTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.Battleground.WarsongGulch
  alias ThistleTea.Game.Battleground.WarsongGulch.Result
  alias ThistleTea.Game.WorldRef

  @alliance 1
  @horde 2
  @alliance_base_guid 101
  @horde_base_guid 102
  @alliance_flag_base 179_830
  @horde_flag_base 179_831
  @alliance_flag_ground 179_785
  @alliance_capture_trigger 3_646

  setup do
    match =
      WorldRef.instance(489, 7)
      |> WarsongGulch.new(7, 5, template(), reservations(), 1_000, start_delay_ms: 120_000)
      |> Map.fetch!(:match)

    %{match: match}
  end

  describe "new/7" do
    test "starts behind closed gates with deterministic countdown and resurrection timers" do
      result =
        WarsongGulch.new(
          WorldRef.instance(489, 7),
          7,
          5,
          template(),
          reservations(),
          1_000,
          start_delay_ms: 120_000
        )

      assert %Result{match: %{phase: :countdown, started_at: 121_000}} = result

      assert result.timers == [
               start_half_minute: 90_000,
               start_one_minute: 60_000,
               start: 120_000,
               resurrection_wave: 120_000
             ]

      assert result.effects == [%Effects.OperateGates{action: :close}]
    end
  end

  describe "handle_timer/3" do
    test "opens the gates and publishes initial UI state when the battle starts", %{match: match} do
      %Result{match: active, effects: effects} = WarsongGulch.handle_timer(match, :start, 121_000)

      assert active.phase == :active
      assert %Effects.OperateGates{action: :open} in effects
      assert %Effects.UpdateWorldStates{states: WarsongGulch.world_states(active)} in effects
    end

    test "resurrects each queued player once and schedules the next wave", %{match: match} do
      match = active_with_players(match)
      match = WarsongGulch.queue_resurrection(match, @alliance).match
      match = WarsongGulch.queue_resurrection(match, @horde).match

      assert %Result{
               match: %{resurrection_queue: queue, next_resurrection_at: 60_000},
               effects: [%Effects.ResurrectPlayers{guids: guids}],
               timers: [resurrection_wave: 30_000]
             } = WarsongGulch.handle_timer(match, :resurrection_wave, 30_000)

      assert queue == MapSet.new()
      assert MapSet.new(guids) == MapSet.new([@alliance, @horde])
    end
  end

  describe "use_game_object/6" do
    test "takes an enemy base flag and updates the carrier UI", %{match: match} do
      match = active_with_players(match)

      assert {:handled, %Result{match: taken, effects: effects}} =
               WarsongGulch.use_game_object(
                 match,
                 @alliance,
                 @horde_base_guid,
                 @horde_flag_base,
                 {1.0, 2.0, 3.0, 0.0},
                 1_000
               )

      assert taken.flags.horde.state == :carried
      assert taken.flags.horde.carrier == @alliance
      assert %Effects.HideGameObject{guid: @horde_base_guid} in effects
      assert %Effects.ApplyFlagAura{guid: @alliance, team: :horde} in effects
      assert {1_546, 1} in WarsongGulch.world_states(taken)
      assert {2_339, 2} in WarsongGulch.world_states(taken)
    end

    test "drops a carried flag on death and returns it after the audited timeout", %{match: match} do
      match = match |> active_with_players() |> take_horde_flag()

      assert %Result{match: dropped, effects: effects, timers: [{{:flag_return, :horde, generation}, 10_000}]} =
               WarsongGulch.player_died(match, @alliance, @horde, {4.0, 5.0, 6.0, 0.0}, 999)

      assert dropped.flags.horde == %WarsongGulch.Flag{
               state: :ground,
               carrier: nil,
               dropped_guid: 999,
               generation: generation
             }

      assert %Effects.SpawnDroppedFlag{guid: 999, team: :horde, position: {4.0, 5.0, 6.0, 0.0}} in effects

      assert %Result{match: returned, effects: return_effects} =
               WarsongGulch.handle_timer(dropped, {:flag_return, :horde, generation}, 11_000)

      assert returned.flags.horde.state == :base
      assert %Effects.DespawnGameObject{guid: 999} in return_effects
      assert %Effects.ShowBaseFlag{team: :horde} in return_effects
    end

    test "lets the owner return a dropped flag and invalidates the stale timer", %{match: match} do
      match = match |> active_with_players() |> take_alliance_flag()
      dropped = WarsongGulch.player_died(match, @horde, @alliance, {0.0, 0.0, 0.0, 0.0}, 777).match
      generation = dropped.flags.alliance.generation

      assert {:handled, %Result{match: returned}} =
               WarsongGulch.use_game_object(
                 dropped,
                 @alliance,
                 777,
                 @alliance_flag_ground,
                 {0.0, 0.0, 0.0, 0.0},
                 2_000
               )

      assert returned.flags.alliance.state == :base
      assert returned.players[@alliance].flag_returns == 1
      assert WarsongGulch.handle_timer(returned, {:flag_return, :alliance, generation}, 12_000).effects == []
    end
  end

  describe "area_trigger/4" do
    test "captures only while the scoring team's own flag is home", %{match: match} do
      match = match |> active_with_players() |> take_horde_flag()

      assert {:handled, %Result{match: captured, timers: [{{:flag_respawn, :horde, generation}, 23_000}]}} =
               WarsongGulch.area_trigger(match, @alliance, @alliance_capture_trigger, 3_000)

      assert captured.team_scores.alliance == 1
      assert captured.players[@alliance].flag_captures == 1
      assert captured.flags.horde.state == :waiting

      respawned = WarsongGulch.handle_timer(captured, {:flag_respawn, :horde, generation}, 26_000).match
      assert respawned.flags.alliance.state == :base
      assert respawned.flags.horde.state == :base
    end

    test "does not capture while the scoring team's flag is away", %{match: match} do
      match = match |> active_with_players() |> take_horde_flag() |> take_alliance_flag()

      assert {:handled, %Result{match: unchanged, effects: []}} =
               WarsongGulch.area_trigger(match, @alliance, @alliance_capture_trigger, 3_000)

      assert unchanged.team_scores.alliance == 0
    end

    test "ends at three captures with rewards, final scoreboard, and auto-leave", %{match: match} do
      match = active_with_players(match)

      ended =
        Enum.reduce(1..3, match, fn capture, match ->
          match = take_horde_flag(match)
          {:handled, result} = WarsongGulch.area_trigger(match, @alliance, @alliance_capture_trigger, capture * 30_000)

          if capture < 3 do
            [{{:flag_respawn, :horde, generation}, _delay}] = result.timers

            WarsongGulch.handle_timer(result.match, {:flag_respawn, :horde, generation}, capture * 30_000 + 23_000).match
          else
            assert result.timers == [auto_leave: 120_000]
            assert Enum.any?(result.effects, &match?(%Effects.Scoreboard{ended?: true, winner: :alliance}, &1))
            assert Enum.any?(result.effects, &match?(%Effects.RewardPlayers{winner: :alliance}, &1))
            result.match
          end
        end)

      assert ended.phase == {:ended, :alliance}
      assert ended.team_scores.alliance == 3
      assert ended.players[@alliance].bonus_honor == 1_386
    end
  end

  describe "player_died/5" do
    test "records opposing killing blows without crediting suicides or teammates", %{match: match} do
      match = active_with_players(match)
      match = WarsongGulch.player_died(match, @alliance, @horde, nil, nil).match
      match = WarsongGulch.player_died(match, @horde, @horde, nil, nil).match

      assert match.players[@alliance].deaths == 1
      assert match.players[@horde].deaths == 1
      assert match.players[@horde].killing_blows == 1
      assert match.players[@horde].honorable_kills == 1
    end
  end

  defp active_with_players(match) do
    match = WarsongGulch.enter(match, @alliance, return_to(1)).match
    match = WarsongGulch.enter(match, @horde, return_to(2)).match
    WarsongGulch.handle_timer(match, :start, 1_000).match
  end

  defp take_horde_flag(match) do
    {:handled, result} =
      WarsongGulch.use_game_object(
        match,
        @alliance,
        @horde_base_guid,
        @horde_flag_base,
        {1.0, 2.0, 3.0, 0.0},
        1_000
      )

    result.match
  end

  defp take_alliance_flag(match) do
    {:handled, result} =
      WarsongGulch.use_game_object(
        match,
        @horde,
        @alliance_base_guid,
        @alliance_flag_base,
        {1.0, 2.0, 3.0, 0.0},
        1_000
      )

    result.match
  end

  defp reservations do
    [
      %{guid: @alliance, name: "Alliance", team: :alliance},
      %{guid: @horde, name: "Horde", team: :horde}
    ]
  end

  defp template do
    %Template{
      type_id: 2,
      map_id: 489,
      min_players_per_team: 1,
      max_players_per_team: 10,
      min_level: 10,
      max_level: 60,
      alliance_start: {WorldRef.open(489), 1.0, 2.0, 3.0, 0.0},
      horde_start: {WorldRef.open(489), 4.0, 5.0, 6.0, 0.0},
      alliance_win_spell: 24_951,
      alliance_lose_spell: 24_950,
      horde_win_spell: 24_951,
      horde_lose_spell: 24_950
    }
  end

  defp return_to(id), do: {WorldRef.open(0), id * 1.0, id * 2.0, id * 3.0, 0.0}
end
