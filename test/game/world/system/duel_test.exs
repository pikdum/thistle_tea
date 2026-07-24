defmodule ThistleTea.Game.World.System.DuelTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem
  alias ThistleTea.Game.WorldRef

  describe "challenge lifecycle" do
    setup do
      parent = self()
      table = :ets.new(:duel_system_test, [:set, :public])
      world = WorldRef.open(0)

      {:ok, server} =
        GenServer.start_link(DuelSystem,
          table: table,
          countdown_ms: 10,
          bounds_tick_ms: 60_000,
          now: fn -> System.monotonic_time(:millisecond) end,
          online?: fn _guid -> true end,
          dueling_allowed?: fn _guid -> true end,
          position: fn
            1 -> {world, 0.0, 0.0, 0.0}
            2 -> {world, 2.0, 0.0, 0.0}
          end,
          player_name: &"Player#{&1}",
          spawn_flag: fn attrs ->
            send(parent, {:spawn_flag, attrs})
            {:ok, 3}
          end,
          despawn_flag: &send(parent, {:despawn_flag, &1}),
          send_packet: &send(parent, {:packet, &2, &1}),
          broadcast_winner: &send(parent, {:winner, &2, &1}),
          sync_player: &send(parent, {:sync, &1, &2}),
          trigger_spell: &send(parent, {:trigger, &1, &2})
        )

      on_exit(fn -> if Process.alive?(server), do: GenServer.stop(server) end)

      attrs = %{
        initiator_guid: 1,
        initiator_level: 20,
        opponent_guid: 2,
        entry: 21_680,
        world: world,
        flag_position: {1.0, 0.0, 0.0},
        orientation: 0.0
      }

      %{server: server, table: table, attrs: attrs}
    end

    test "spawns a flag, counts down, starts, and completes a duel", %{
      server: server,
      table: table,
      attrs: attrs
    } do
      assert {:ok, match} = DuelSystem.challenge(attrs, server)
      assert match.state == :requested
      assert_receive {:spawn_flag, ^attrs}
      assert_receive {:sync, 1, {:requested, %{opponent_guid: 2, arbiter_guid: 3}}}
      assert_receive {:sync, 2, {:requested, %{opponent_guid: 1, arbiter_guid: 3}}}
      assert_receive {:packet, 1, %Message.SmsgDuelRequested{arbiter_guid: 3, initiator_guid: 1}}
      assert_receive {:packet, 2, %Message.SmsgDuelRequested{arbiter_guid: 3, initiator_guid: 1}}

      assert :ok = DuelSystem.accept(2, server)
      assert_receive {:packet, 1, %Message.SmsgDuelCountdown{time_ms: 10}}
      assert_receive {:packet, 2, %Message.SmsgDuelCountdown{time_ms: 10}}
      assert_receive {:sync, 1, {:started, %{opponent_guid: 2, team: 1}}}, 100
      assert_receive {:sync, 2, {:started, %{opponent_guid: 1, team: 2}}}, 100
      assert DuelSystem.active_opponents?(1, 2, table)

      assert :ok = DuelSystem.cancel(2, server)
      assert_receive {:packet, 1, %Message.SmsgDuelComplete{started?: true}}
      assert_receive {:packet, 2, %Message.SmsgDuelComplete{started?: true}}
      assert_receive {:winner, 2, %Message.SmsgDuelWinner{fled?: false, winner_name: "Player1", loser_name: "Player2"}}
      assert_receive {:trigger, 2, 7_267}
      assert_receive {:despawn_flag, 3}
      refute DuelSystem.active_opponents?(1, 2, table)
    end

    test "a disconnect forfeits an active duel", %{server: server, attrs: attrs} do
      assert {:ok, _match} = DuelSystem.challenge(attrs, server)
      assert :ok = DuelSystem.accept(2, server)
      assert_receive {:sync, 1, {:started, _payload}}, 100

      assert :ok = DuelSystem.disconnect(1, server)
      assert_receive {:winner, 1, %Message.SmsgDuelWinner{fled?: true, winner_name: "Player2", loser_name: "Player1"}}
      refute_received {:trigger, 1, 7_267}
      assert DuelSystem.match(1, server) == nil
    end
  end
end
