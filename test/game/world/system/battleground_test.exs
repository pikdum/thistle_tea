defmodule ThistleTea.Game.World.System.BattlegroundTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Battleground.Effects.OperateGates
  alias ThistleTea.Game.Battleground.Template
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

    def template_for_map(_map), do: nil
    def gate_entries, do: []
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
      assert Enum.map(BattlegroundSystem.scoreboard(world, server), & &1.guid) == [2]

      assert :ok = BattlegroundSystem.join(alliance(3), 489, server)
      assert %{status: :wait_join, client_instance_id: 1} = BattlegroundSystem.status(3, server)
    end
  end

  defp alliance(guid), do: %{guid: guid, name: "Alliance#{guid}", team: :alliance, level: 60}
  defp horde(guid), do: %{guid: guid, name: "Horde#{guid}", team: :horde, level: 60}
end
