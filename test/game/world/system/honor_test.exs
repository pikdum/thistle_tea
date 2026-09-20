defmodule ThistleTea.Game.World.System.HonorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Data.Honor.Snapshot
  alias ThistleTea.Game.World.HonorStore
  alias ThistleTea.Game.World.System.Honor

  setup [:start_honor]

  describe "player_kill/3" do
    test "serializes repeated kills and sends only positive awards", %{server: server} do
      register_players(server)
      Honor.player_kill(2, %{1 => 1.0}, server)
      Honor.player_kill(2, %{1 => 1.0}, server)
      assert %Snapshot{honor: honor} = Honor.snapshot(1, server)
      assert honor.lifetime_honorable_kills == 2
      assert honor.days[5].contribution == 357
      assert_receive {:honor, 1, %Award{points: 188, victim_guid: 2, victim_rank: 5}}
      assert_receive {:honor, 1, %Award{points: 169}}

      for _ <- 1..10, do: Honor.player_kill(2, %{1 => 1.0}, server)
      assert Honor.snapshot(1, server).honor.lifetime_honorable_kills == 10
      refute_received {:honor, 2, %Award{}}
    end

    test "keeps contributions across a coordinator restart", %{server: server, opts: opts, table: table} do
      register_players(server)
      Honor.player_kill(2, %{1 => 1.0}, server)
      before_restart = Honor.snapshot(1, server)
      assert :ok = stop_supervised(Honor)
      assert :ets.info(table, :owner) == self()
      restarted = start_supervised!({Honor, opts})
      assert Honor.snapshot(1, restarted) == before_restart
      Honor.player_kill(2, %{1 => 1.0}, restarted)
      assert Honor.snapshot(1, restarted).honor.days[5].contribution == 357
    end
  end

  describe "calendar settlement" do
    test "settles before the first award after midnight", %{server: server, clock: clock} do
      register_players(server)
      Honor.player_kill(2, %{1 => 1.0}, server)
      assert Honor.snapshot(1, server).honor.days[5].contribution == 188
      :atomics.put(clock, 1, 6)
      Honor.player_kill(2, %{1 => 1.0}, server)
      snapshot = Honor.snapshot(1, server)
      assert snapshot.day == 6
      assert snapshot.honor.days[6].contribution == 188
      assert_receive {:honor, 1, nil}
      assert_receive {:honor, 2, nil}
    end

    test "settles offline characters and resumes after missed weeks", %{server: server, clock: clock, table: table} do
      register_players(server)
      for _ <- 1..15, do: Honor.award(1, %Award{type: :honorable, points: 100}, server)
      assert Honor.snapshot(1, server).honor.lifetime_honorable_kills == 15
      :atomics.put(clock, 1, 12)
      send(server, :tick)
      snapshot = Honor.snapshot(1, server)
      assert snapshot.week_start == 12
      assert snapshot.honor.rank_points == 3000
      assert snapshot.honor.last_week.contribution == 1500
      assert snapshot.honor.last_standing == 1
      assert HonorStore.load(12, 2, table).entries[1].honor == snapshot.honor
      :atomics.put(clock, 1, 26)
      snapshot = Honor.snapshot(1, server)
      assert snapshot.honor.rank_points == 2430
      assert snapshot.honor.highest_rank == 6
      assert snapshot.honor.last_week.honorable_kills == 0
    end

    test "refreshing a profile preserves its ledger", %{server: server} do
      register_players(server)
      Honor.player_kill(2, %{1 => 1.0}, server)
      before_update = Honor.snapshot(1, server)
      assert Honor.register(1, :alliance, 59, server) == before_update
      Honor.player_kill(2, %{1 => 1.0}, server)
      assert Honor.snapshot(1, server).honor.days[5].contribution == 357
    end
  end

  defp register_players(server) do
    Honor.register(1, :alliance, 60, server)
    Honor.register(2, :horde, 60, server)
  end

  defp start_honor(_context) do
    owner = self()
    table = :ets.new(:honor_test, [:set, :public])
    clock = :atomics.new(1, signed: true)
    :atomics.put(clock, 1, 5)

    opts = [
      name: nil,
      table: table,
      tick_ms: nil,
      day: fn -> :atomics.get(clock, 1) end,
      notify: fn guid, award -> send(owner, {:honor, guid, award}) end
    ]

    %{server: start_supervised!({Honor, opts}), opts: opts, table: table, clock: clock}
  end
end
