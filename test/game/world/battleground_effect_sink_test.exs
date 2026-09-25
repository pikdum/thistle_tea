defmodule ThistleTea.Game.World.BattlegroundEffectSinkTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Player
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.Battleground.WarsongGulch
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Battleground.EffectSink
  alias ThistleTea.Game.World.System.Honor
  alias ThistleTea.Game.WorldRef

  describe "emit/2" do
    test "delivers departure penalties to the departing player's owner" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      Entity.register(guid)
      match = %WarsongGulch{world: WorldRef.instance(489, 7), client_instance_id: 7, bracket: 5, template: %Template{}}
      assert :ok = EffectSink.emit(match, [%Effects.ApplyDeserter{guid: guid}])
      assert_receive {:"$gen_cast", :battleground_deserted}
    end

    test "schedules random-delay timers on the explicitly supplied match owner" do
      parent = self()
      owner = spawn(fn -> receive do: (message -> send(parent, {:owner_received, message})) end)
      on_exit(fn -> Process.exit(owner, :shutdown) end)
      match = %WarsongGulch{world: WorldRef.instance(489, 7), client_instance_id: 7, bracket: 5, template: %Template{}}
      effect = %Effects.ScheduleTimer{key: {:captain_buff, :alliance}, delays: [120_000, 180_000]}
      choose = fn [120_000, 180_000] -> 0 end
      assert :ok = EffectSink.emit(match, [effect], owner: owner, choose_delay: choose)
      assert_receive {:owner_received, {:battleground_timer, {:captain_buff, :alliance}}}
      refute_received {:battleground_timer, _key}
    end

    test "routes timed and trigger exits through the player's resurrection cleanup" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      Entity.register(guid)
      world = WorldRef.open(0)
      position = {1.0, 2.0, 3.0, 4.0}
      match = %WarsongGulch{world: WorldRef.instance(489, 7), client_instance_id: 7, bracket: 5, template: %Template{}}

      EffectSink.emit(match, [%Effects.ExitPlayers{destinations: %{guid => {world, position}}}])
      assert_receive {:"$gen_cast", {:battleground_exit, ^world, ^position}}
    end

    test "publishes the victory exit countdown immediately" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      Entity.register(guid)
      now = Time.now()

      match = %WarsongGulch{
        world: WorldRef.instance(489, 7),
        client_instance_id: 7,
        bracket: 5,
        template: %Template{},
        phase: {:ended, :alliance},
        started_at: now - 180_000,
        ended_at: now - 1_000,
        players: %{guid => %Player{guid: guid, name: "Debug", team: :alliance, status: :inside}}
      }

      EffectSink.emit(match, [%Effects.UpdateStatus{}])

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgBattlefieldStatus{time_one_ms: remaining, time_two_ms: elapsed}}}

      assert remaining > 118_000 and remaining <= 119_000
      assert elapsed >= 180_000
    end

    test "credits the realm ledger and notifies the owner without adding a kill" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      Entity.register(guid)
      Honor.register(guid, :alliance, 60)
      match = %WarsongGulch{world: WorldRef.instance(489, 7), client_instance_id: 7, bracket: 5, template: %Template{}}

      assert :ok = EffectSink.emit(match, [%Effects.RewardHonor{guids: [guid], amount: 396}])
      snapshot = Honor.snapshot(guid)
      assert snapshot.honor.days[snapshot.day].contribution == 396
      assert snapshot.honor.lifetime_honorable_kills == 0
      assert_receive {:"$gen_cast", {:honor_updated, %{type: :bonus, points: 396}}}
    end
  end

  test "publishes a nonzero active-match runtime to inside players" do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
    assert {:ok, _owner} = Entity.register(guid)

    match = %WarsongGulch{
      world: WorldRef.instance(489, 7),
      client_instance_id: 7,
      bracket: 5,
      template: %Template{},
      started_at: Time.now() - 1_000,
      players: %{
        guid => %Player{guid: guid, name: "Debug", team: :alliance, status: :inside}
      }
    }

    assert :ok = EffectSink.emit(match, [%Effects.UpdateStatus{}])

    assert_receive {:"$gen_cast",
                    {:send_packet,
                     %Message.SmsgBattlefieldStatus{
                       map: 489,
                       bracket: 5,
                       client_instance_id: 7,
                       status: :in_progress,
                       time_one_ms: 0,
                       time_two_ms: elapsed_ms
                     }}}

    assert elapsed_ms >= 1_000
  end
end
