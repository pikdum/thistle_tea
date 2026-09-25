defmodule ThistleTea.Game.World.System.BattlegroundTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Battleground.CreatureDefeat
  alias ThistleTea.Game.Battleground.Defeat
  alias ThistleTea.Game.Battleground.Effects.OperateGates
  alias ThistleTea.Game.Battleground.Effects.Scoreboard
  alias ThistleTea.Game.Battleground.Effects.UpdateStatus
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Battleground.Match
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.WorldRef

  defmodule Catalog do
    @moduledoc false

    def template_for_map(489) do
      %Template{
        type_id: 2,
        map_id: 489,
        min_players_per_team: 1,
        max_players_per_team: 2,
        min_level: 10,
        max_level: 60,
        alliance_start: {1.0, 2.0, 3.0, 4.0},
        horde_start: {5.0, 6.0, 7.0, 8.0},
        alliance_graveyard: {9.0, 10.0, 11.0, 12.0},
        horde_graveyard: {13.0, 14.0, 15.0, 16.0},
        alliance_win_spell: 24_951,
        alliance_lose_spell: 24_950,
        horde_win_spell: 24_951,
        horde_lose_spell: 24_950
      }
    end

    def template_for_map(30) do
      %{template_for_map(489) | type_id: 1, map_id: 30, min_level: 51}
    end

    def template_for_map(_map), do: nil
    def gate_entries(_map_id), do: []
    def ghost_gate_entries(_map_id), do: [180_322]
  end

  setup do
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)
    name = {:global, {__MODULE__, make_ref()}}
    owner = self()

    {:ok, server} =
      BattlegroundSystem.start_link(
        name: name,
        catalog: Catalog,
        match_supervisor: supervisor,
        effect_sink: fn _match, effects -> send(owner, {:effects, effects}) end,
        match_options: [start_delay_ms: 120_000]
      )

    %{server: server, supervisor: supervisor}
  end

  describe "join_group/3" do
    test "routes quest donations and revalidates serialized blacksmith upgrades", %{server: server} do
      assert :ok = BattlegroundSystem.join(%{alliance(1) | level: 60}, 30, server)
      assert :ok = BattlegroundSystem.join(%{horde(2) | level: 60}, 30, server)
      destination = {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}
      assert {:ok, world, _} = BattlegroundSystem.port(1, 1, destination, server)
      assert {:ok, ^world, _} = BattlegroundSystem.port(2, 1, destination, server)
      assert :ok = BattlegroundSystem.debug_start_now(world, server)

      for _ <- 1..25, do: BattlegroundSystem.quest_rewarded(world, 1, 6_781, server)

      assert %{options: [_, %{action: {:upgrade_armor, 1}}]} =
               BattlegroundSystem.gossip(world, 1, 13_257, 9_000, server)

      assert BattlegroundSystem.gossip(world, 2, 13_257, 9_000, server) == nil
      assert BattlegroundSystem.gossip(WorldRef.instance(30, 999), 1, 13_257, 9_000, server) == nil
      assert :close = BattlegroundSystem.interact(world, 1, 13_257, {:upgrade_armor, 1}, 8_999, server)
      pid = BattlegroundSystem.match_for_world(world, server)
      assert Match.snapshot(pid).armor.alliance.tier == 0
      assert :close = BattlegroundSystem.interact(world, 1, 13_257, {:upgrade_armor, 1}, 9_000, server)
      assert Match.snapshot(pid).armor.alliance.tier == 1
      assert :close = BattlegroundSystem.interact(world, 1, 13_257, {:upgrade_armor, 1}, 9_000, server)
      assert Match.snapshot(pid).armor.alliance.tier == 1
      assert Match.snapshot(pid).armor.horde.tier == 0
    end

    test "admits levels 51 and 60 to one Alterac match and routes creature objectives", %{server: server} do
      assert :ok = BattlegroundSystem.join_group([%{alliance(1) | level: 51}, alliance(3)], 30, server)
      assert :ok = BattlegroundSystem.join(horde(2), 30, server)
      assert %{status: :wait_join, bracket: 0} = BattlegroundSystem.status(1, server)
      assert %{status: :wait_join, bracket: 0} = BattlegroundSystem.status(3, server)
      return_to = {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}
      assert {:ok, world, _position} = BattlegroundSystem.port(1, 1, return_to, server)
      assert {:ok, ^world, _position} = BattlegroundSystem.port(2, 1, return_to, server)
      assert world.map_id == 30
      assert :ok = BattlegroundSystem.debug_start_now(world, server)
      refute BattlegroundSystem.supply_allowed?(world, 1, 178_785, server)

      defeat = %CreatureDefeat{
        victim_guid: 100,
        entry: 11_678,
        db_guid: 200,
        incarnation_id: 1,
        killer_guid: 1,
        bindings: [%{event1: 46, event2: 2}]
      }

      BattlegroundSystem.creature_died(world, defeat, server)
      assert BattlegroundSystem.supply_allowed?(world, 1, 178_785, server)
      refute BattlegroundSystem.supply_allowed?(world, 2, 178_785, server)
      refute BattlegroundSystem.supply_allowed?(world, 3, 178_785, server)
      refute BattlegroundSystem.supply_allowed?(WorldRef.instance(30, 999), 1, 178_785, server)
      refute BattlegroundSystem.supply_allowed?(world, 1, 178_784, server)

      general = %{defeat | victim_guid: 101, db_guid: 201, incarnation_id: 2, bindings: [%{event1: 62, event2: 0}]}
      BattlegroundSystem.creature_died(world, general, server)
      assert %{ended?: true, winner: :alliance} = BattlegroundSystem.scoreboard(world, server)
      refute BattlegroundSystem.supply_allowed?(world, 1, 178_785, server)
    end

    test "forms an isolated match and admits invited players to faction starts", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert %{status: :wait_queue, bracket: 5} = BattlegroundSystem.status(1, server)

      assert :ok = BattlegroundSystem.join(horde(2), 489, server)
      assert_receive {:effects, [%OperateGates{action: :close}]}

      assert %{status: :wait_join, client_instance_id: 1} = BattlegroundSystem.status(1, server)
      assert %{status: :wait_join, client_instance_id: 1} = BattlegroundSystem.status(2, server)

      return_to = {WorldRef.open(0), {10.0, 20.0, 30.0, 0.5}}

      assert {:ok, %WorldRef{map_id: 489, instance_id: 1}, {1.0, 2.0, 3.0, 4.0}} =
               BattlegroundSystem.port(1, 1, return_to, server)

      assert %{status: :in_progress, client_instance_id: 1} = BattlegroundSystem.status(1, server)
      world = WorldRef.instance(489, 1)
      assert %{map_id: 489, phase: :countdown} = BattlegroundSystem.spell_context(world, 1, server)
      assert BattlegroundSystem.spell_context(world, 2, server) == nil
      assert BattlegroundSystem.spell_context(WorldRef.instance(489, 2), 1, server) == nil
    end

    test "creates distinct world copies for independently matched teams", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert :ok = BattlegroundSystem.join(horde(2), 489, server)
      assert :ok = BattlegroundSystem.join(alliance(3), 489, server)
      assert :ok = BattlegroundSystem.join(horde(4), 489, server)
      assert :ok = BattlegroundSystem.join(alliance(5), 489, server)
      assert :ok = BattlegroundSystem.join(horde(6), 489, server)

      assert %{client_instance_id: first} = BattlegroundSystem.status(1, server)
      assert %{client_instance_id: ^first} = BattlegroundSystem.status(3, server)
      assert %{client_instance_id: second} = BattlegroundSystem.status(5, server)
      assert first != second
    end

    test "rejects an unavailable client-selected instance without queueing", %{server: server} do
      assert {:error, :invalid_instance} =
               BattlegroundSystem.join_group_for_instance([alliance(1)], 489, 99, server)

      assert %{status: :none} = BattlegroundSystem.status(1, server)
    end

    test "rejects a mixed-bracket group atomically", %{server: server} do
      players = [alliance(1), %{alliance(3) | level: 59}]

      assert {:error, :mixed_bracket} = BattlegroundSystem.join_group(players, 489, server)
      assert %{status: :none} = BattlegroundSystem.status(1, server)
      assert %{status: :none} = BattlegroundSystem.status(3, server)
    end

    test "removes a declined invitation from the match and frees its slot", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert :ok = BattlegroundSystem.join(horde(2), 489, server)
      world = WorldRef.instance(489, 1)

      assert :ok = BattlegroundSystem.port(1, 0, nil, server)
      assert %{status: :none} = BattlegroundSystem.status(1, server)
      assert Enum.map(BattlegroundSystem.scoreboard(world, server).players, & &1.guid) == [2]

      assert :ok = BattlegroundSystem.join(alliance(3), 489, server)
      assert %{status: :wait_join, client_instance_id: 1} = BattlegroundSystem.status(3, server)
    end

    test "stops the isolated world after its final reservation leaves", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert :ok = BattlegroundSystem.join(horde(2), 489, server)
      world = WorldRef.instance(489, 1)
      pid = BattlegroundSystem.match_for_world(world, server)
      ref = Process.monitor(pid)

      assert :ok = BattlegroundSystem.port(1, 0, nil, server)
      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 50
      assert :ok = BattlegroundSystem.port(2, 0, nil, server)
      assert BattlegroundSystem.match_for_world(world, server) == nil
      assert %{instances: []} = BattlegroundSystem.list(489, 60, server)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "ignores stopped matches before their monitor notifications arrive", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert :ok = BattlegroundSystem.join(horde(2), 489, server)
      world = WorldRef.instance(489, 1)
      pid = BattlegroundSystem.match_for_world(world, server)
      join_ref = make_ref()
      list_ref = make_ref()

      :sys.suspend(server)
      send(server, {:"$gen_call", {self(), join_ref}, {:join_group, [alliance(3)], 489, 0}})
      send(server, {:"$gen_call", {self(), list_ref}, {:list, 489, 60}})
      GenServer.stop(pid, :normal)
      :sys.resume(server)

      assert_receive {^join_ref, :ok}
      assert_receive {^list_ref, %{instances: []}}
      assert %{status: :wait_queue} = BattlegroundSystem.status(3, server)
      assert BattlegroundSystem.match_for_world(world, server) == nil
      assert Process.alive?(server)
    end
  end

  describe "corpse_recovery_allowed?/3" do
    test "permits only admitted players after preparation ends", %{server: server} do
      :ok = BattlegroundSystem.join(alliance(1), 489, server)
      :ok = BattlegroundSystem.join(horde(2), 489, server)
      world = WorldRef.instance(489, 1)
      return_to = {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}
      {:ok, ^world, _position} = BattlegroundSystem.port(1, 1, return_to, server)
      refute BattlegroundSystem.corpse_recovery_allowed?(world, 1, server)
      :ok = BattlegroundSystem.debug_start_now(world, server)
      assert BattlegroundSystem.corpse_recovery_allowed?(world, 1, server)
      refute BattlegroundSystem.corpse_recovery_allowed?(world, 2, server)
      refute BattlegroundSystem.corpse_recovery_allowed?(WorldRef.instance(489, 999), 1, server)
      BattlegroundSystem.leave(1, {0.0, 0.0, 0.0, 0.0}, server)
      refute BattlegroundSystem.corpse_recovery_allowed?(world, 1, server)
    end
  end

  describe "player_died/3" do
    test "routes defeat credit and exposes only the admitted roster", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert :ok = BattlegroundSystem.join(horde(2), 489, server)
      assert :ok = BattlegroundSystem.join(alliance(3), 489, server)
      return_to = {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}

      assert {:ok, world, _position} = BattlegroundSystem.port(1, 1, return_to, server)
      assert {:ok, ^world, _position} = BattlegroundSystem.port(2, 1, return_to, server)
      assert Enum.sort(Map.keys(BattlegroundSystem.participants(world, server))) == [1, 2]
      assert {:ok, ^world, _position} = BattlegroundSystem.port(3, 1, return_to, server)
      assert :ok = BattlegroundSystem.debug_start_now(world, server)

      defeat = %Defeat{victim_guid: 2, killer_guid: 1, position: {0.0, 0.0, 0.0, 0.0}, nearby_guids: [1, 3]}
      BattlegroundSystem.player_died(world, defeat, server)
      players = BattlegroundSystem.participants(world, server)
      assert players[1].killing_blows == 1
      assert players[1].honorable_kills == 1
      assert players[3].killing_blows == 0
      assert players[3].honorable_kills == 1
      assert players[2].deaths == 1

      BattlegroundSystem.disconnect(3, {0.0, 0.0, 0.0, 0.0}, server)
      refute Map.has_key?(BattlegroundSystem.participants(world, server), 3)
      assert BattlegroundSystem.participants(WorldRef.instance(489, 99), server) == %{}
    end
  end

  describe "debug controls" do
    test "retains the winner and scores in repeated queries after victory", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert {:ok, _status} = BattlegroundSystem.debug_start_queued(1, server)
      assert {:ok, world, _position} = BattlegroundSystem.port(1, 1, nil, server)
      assert :ok = BattlegroundSystem.debug_start_now(world, server)
      pid = BattlegroundSystem.match_for_world(world, server)

      for capture <- 1..3 do
        assert :handled = Match.use_game_object(pid, 1, 100, 179_831, {0.0, 0.0, 0.0, 0.0})
        assert :handled = Match.area_trigger(pid, 1, 3646, nil, nil)
        if capture < 3, do: send(pid, {:battleground_timer, {:flag_respawn, :horde, capture * 2}})
      end

      for _query <- 1..2 do
        assert %Scoreboard{ended?: true, winner: :alliance, players: [player]} =
                 BattlegroundSystem.scoreboard(world, server)

        assert player.bonus_honor == 1386
        assert player.fields == [3, 0]
      end

      assert %{auto_leave_ms: remaining} = BattlegroundSystem.status(1, server)
      assert remaining > 119_000 and remaining <= 120_000
    end

    test "invites one queued player into an isolated match and starts it immediately", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert %{status: :wait_queue} = BattlegroundSystem.status(1, server)

      assert {:ok, %{status: :wait_join, client_instance_id: 1}} =
               BattlegroundSystem.debug_start_queued(1, server)

      assert_receive {:effects, [%OperateGates{action: :close}]}

      assert %{
               status: :wait_join,
               phase: :countdown,
               scores: %{alliance: 0, horde: 0},
               objectives: %{alliance: :base, horde: :base},
               players: %{alliance: 1, horde: 0, inside: 0}
             } = BattlegroundSystem.debug_info(1, server)

      return_to = {WorldRef.open(0), {10.0, 20.0, 30.0, 0.5}}

      assert {:ok, %WorldRef{} = world, _destination} =
               BattlegroundSystem.port(1, 1, return_to, server)

      assert_receive {:effects, [_player_joined]}
      assert :ok = BattlegroundSystem.debug_start_now(world, server)
      assert_receive {:effects, effects}
      assert Enum.any?(effects, &match?(%OperateGates{action: :open}, &1))

      send(pid = BattlegroundSystem.match_for_world(world, server), {:battleground_timer, :status_refresh})
      assert_receive {:effects, [%UpdateStatus{}, _scoreboard]}
      assert Process.alive?(pid)

      assert %{status: :in_progress, phase: :active, players: %{inside: 1}} =
               BattlegroundSystem.debug_info(1, server)

      assert {:error, :not_counting_down} = BattlegroundSystem.debug_start_now(world, server)
    end

    test "rejects solo admission unless the player is queued", %{server: server} do
      assert {:error, :not_queued} = BattlegroundSystem.debug_start_queued(1, server)

      assert {:error, :not_in_battleground} =
               BattlegroundSystem.debug_start_now(WorldRef.instance(489, 99), server)
    end

    test "removes ghost gates that load after the battle starts", %{server: server} do
      assert :ok = BattlegroundSystem.join(alliance(1), 489, server)
      assert {:ok, _status} = BattlegroundSystem.debug_start_queued(1, server)
      assert {:ok, %WorldRef{} = world, _destination} = BattlegroundSystem.port(1, 1, nil, server)
      assert :ok = BattlegroundSystem.debug_start_now(world, server)

      guid = Guid.runtime(:game_object, 180_322)
      assert {:ok, _owner} = Entity.register(guid)

      BattlegroundSystem.game_object_spawned(world, guid, 180_322, server)
      BattlegroundSystem.status(1, server)

      assert_receive {:"$gen_cast", {:battleground_hide_game_object}}
    end
  end

  defp alliance(guid), do: %{guid: guid, name: "Alliance#{guid}", team: :alliance, level: 60}
  defp horde(guid), do: %{guid: guid, name: "Horde#{guid}", team: :horde, level: 60}
end
