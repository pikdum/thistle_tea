defmodule ThistleTea.Game.World.System.Battleground.BattlegroundEffectSinkTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Player
  alias ThistleTea.Game.Core.Battleground.Template
  alias ThistleTea.Game.Core.Battleground.WarsongGulch
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Loader.BroadcastText
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Battleground.EffectSink
  alias ThistleTea.Game.World.System.Honor
  alias ThistleTea.Test.Unique

  describe "emit/2" do
    test "a replacement deployment targets its own commander in the match's copy" do
      world = WorldRef.instance(30, Unique.integer())
      other_world = WorldRef.instance(30, Unique.integer())
      commander = Guid.from_low_guid(:mob, 13_446, Unique.integer())
      stale = Guid.from_low_guid(:mob, 13_446, Unique.integer())
      other = Guid.from_low_guid(:mob, 13_446, Unique.integer())

      for {guid, copy} <- [{commander, world}, {stale, world}, {other, other_world}] do
        {:ok, _} = Entity.register(guid)
        SpatialHash.insert(:mobs, guid, copy, 0.0, 0.0, 0.0)
      end

      on_exit(fn -> for guid <- [commander, stale, other], do: SpatialHash.remove(:mobs, guid) end)
      steps = [%ScriptStep{command: :send_script_event, datalong: 1}]
      effect = %Effects.RunCreatureScript{creature_entry: 13_446, creature_guid: commander, steps: steps}
      assert :ok = EffectSink.emit(%{world: world, players: %{}}, [effect])
      assert_receive {:"$gen_cast", {:start_script, ^steps, ^commander, ^world}}
      refute_received {:"$gen_cast", {:start_script, _, _, _}}
    end

    test "runs voiced creature scripts only in the match's copy" do
      world = WorldRef.instance(30, Unique.integer())
      other_world = WorldRef.instance(30, Unique.integer())
      summoner = Guid.from_low_guid(:mob, 13_442, Unique.integer())
      other_summoner = Guid.from_low_guid(:mob, 13_442, Unique.integer())
      wrong_entry = Guid.from_low_guid(:mob, 13_236, Unique.integer())
      text_id = Unique.integer()
      line = %{text: "Aid and protect us!", chat_type: :yell, language: 0, emote_id: 0}
      :ets.insert(BroadcastText, {text_id, line})

      for {guid, copy} <- [{summoner, world}, {other_summoner, other_world}, {wrong_entry, world}] do
        {:ok, _} = Entity.register(guid)
        SpatialHash.insert(:mobs, guid, copy, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [summoner, other_summoner, wrong_entry], do: SpatialHash.remove(:mobs, guid)
        :ets.delete(BroadcastText, text_id)
      end)

      match = %{world: world, players: %{}}
      steps = [%ScriptStep{command: :talk, dataint: text_id}, %ScriptStep{command: :start_waypoints, datalong: 5}]
      assert :ok = EffectSink.emit(match, [%Effects.RunCreatureScript{creature_entry: 13_442, steps: steps}])
      assert_receive {:"$gen_cast", {:start_script, [talk, route], ^summoner, ^world}}
      assert talk.texts == [line]
      assert route == List.last(steps)
      refute_received {:"$gen_cast", {:start_script, _, _, _}}
    end

    test "keeps the offline carrier's name after live metadata disappears" do
      observer = Unique.integer()
      carrier = Unique.integer()
      text_id = Unique.integer()
      {:ok, _} = Entity.register(observer)
      :ets.insert(BroadcastText, {text_id, %{text: "The Horde Flag was dropped by $n!"}})
      on_exit(fn -> :ets.delete(BroadcastText, text_id) end)

      match = %WarsongGulch{
        world: WorldRef.instance(489, 7),
        client_instance_id: 7,
        bracket: 5,
        template: %Template{},
        players: %{
          observer => %Player{guid: observer, name: "Observer", team: :alliance, status: :inside},
          carrier => %Player{guid: carrier, name: "Carrier", team: :alliance, status: :offline}
        }
      }

      EffectSink.emit(match, [%Effects.Announce{broadcast_text_id: text_id, audience: :alliance, actor_guid: carrier}])

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgMessagechat{
                         sender_guid: ^carrier,
                         message: "The Horde Flag was dropped by Carrier!"
                       }}}
    end

    test "delivers departure penalties to the departing player's owner" do
      guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(guid)
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
      guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(guid)
      world = WorldRef.open(0)
      position = {1.0, 2.0, 3.0, 4.0}
      match = %WarsongGulch{world: WorldRef.instance(489, 7), client_instance_id: 7, bracket: 5, template: %Template{}}

      EffectSink.emit(match, [%Effects.ExitPlayers{destinations: %{guid => {world, position}}}])
      assert_receive {:"$gen_cast", {:battleground_exit, ^world, ^position}}
    end

    test "publishes the victory exit countdown immediately" do
      guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(guid)
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
      guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(guid)
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
    guid = Guid.from_low_guid(:player, Unique.integer())
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
