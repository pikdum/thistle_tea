defmodule ThistleTea.Game.World.Visibility.QuestGiversTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestGraph
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgQuestgiverStatus
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.PacketSink
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.ServerVariables
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.Topics
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.World.Visibility.QuestGivers
  alias ThistleTea.Game.World.Visibility.QuestGivers.Watch

  setup [:questgiver]

  describe "refresh/1" do
    test "refreshes stationary viewers when the world event starts and stops", context do
      saved = GameEvent.get_events()
      on_exit(fn -> GameEvent.set_events(saved) end)
      quest = %{context.quest | required_skill: 0, event_id: context.quest.id}
      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})

      state = refresh_and_deliver(context.state, context.guid, 0)
      GameEvent.set_events([quest.event_id | saved])
      state = refresh_and_deliver(state, context.guid, 5)
      GameEvent.set_events(saved)
      state = refresh_and_deliver(state, context.guid, 0)
      QuestGivers.refresh(state)
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}
    end

    test "refreshes visible NPC eligibility after skill changes and deduplicates sent statuses", context do
      state = refresh_and_deliver(context.state, context.guid, 0)
      QuestGivers.refresh(state)
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}

      player = %{state.character.player | skills: %{185 => %{value: 49}}}
      state = %{state | character: %{state.character | player: player}}
      QuestGivers.refresh(state)
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}

      player = %{player | skill_bonuses: %{185 => {1, 0}}}
      eligible = %{state | character: %{state.character | player: player}}
      eligible = refresh_and_deliver(eligible, context.guid, 5)
      assert eligible.questgiver_statuses == %{context.guid => 5}
      QuestGivers.refresh(eligible)
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}

      state = %{eligible | character: state.character}
      state = refresh_and_deliver(state, context.guid, 0)
      assert state.questgiver_statuses == %{context.guid => 0}
    end

    test "projects exclusive rewards independently for each viewer", context do
      [quest, alternative] =
        QuestGraph.compile([
          %{context.quest | required_skill: 0, exclusive_group: context.quest.id},
          %Quest{id: context.quest.id + 1, exclusive_group: context.quest.id}
        ])

      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      state = refresh_and_deliver(context.state, context.guid, 5)
      player = %{state.character.player | rewarded_quests: MapSet.new([alternative.id])}
      excluded = %{state | character: %{state.character | player: player}}
      excluded = refresh_and_deliver(excluded, context.guid, 0)
      assert excluded.questgiver_statuses == %{context.guid => 0}
      assert state.questgiver_statuses == %{context.guid => 5}
      QuestGivers.refresh(state)
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}
    end

    test "forgets removed NPCs, rejects queued stale packets, and clears removed questgiver flags", context do
      state = refresh_and_deliver(context.state, context.guid, 0)
      removed = Visibility.untrack_entity(state, context.guid)
      assert removed.questgiver_statuses == %{}
      assert QuestGivers.refresh(removed).questgiver_statuses == %{}
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}
      packet = %SmsgQuestgiverStatus{guid: context.guid, status: 5}
      assert PacketSink.send(removed, packet, source_guid: context.guid) == removed
      refute_received {:"$gen_cast", {:write_packet, _}}

      player = %{state.character.player | skills: %{185 => %{value: 50}}}

      restored = %{
        removed
        | character: %{removed.character | player: player},
          tracked_entities: MapSet.new([context.guid])
      }

      restored = refresh_and_deliver(restored, context.guid, 5)
      Metadata.update(context.guid, %{npc_flags: 0})
      restored = refresh_and_deliver(restored, context.guid, 0)
      QuestGivers.refresh(restored)
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}

      pruned = QuestGivers.refresh(%{restored | tracked_entities: MapSet.new()})
      assert pruned.questgiver_statuses == %{}
    end
  end

  describe "sync/1" do
    test "learning and unlearning a required spell refreshes stationary status", context do
      quest = %{
        context.quest
        | required_skill: 0,
          required_condition_id: 1,
          required_condition: %Condition{type: :spell, value1: 123, value2: 0}
      }

      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      state = sync_and_deliver(context.state, context.guid, 0)
      internal = %{state.character.internal | spellbook: %{123 => true}}
      state = sync_and_deliver(%{state | character: %{state.character | internal: internal}}, context.guid, 5)
      internal = %{internal | spellbook: %{}}
      sync_and_deliver(%{state | character: %{state.character | internal: internal}}, context.guid, 0)
    end

    test "health requirements refresh without watching unrelated resource changes", context do
      quest = %{
        context.quest
        | required_skill: 0,
          required_condition_id: 1,
          required_condition: %Condition{type: :health_percent, value1: 50, value2: 1}
      }

      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      state = sync_and_deliver(context.state, context.guid, 5)
      unit = %{state.character.unit | health: 20}
      state = sync_and_deliver(%{state | character: %{state.character | unit: unit}}, context.guid, 0)
      assert QuestGivers.sync(state) == state
    end

    test "saved variables notify only subscribed requirements and clean up on leave", context do
      index = context.quest.id
      original = ServerVariables.get(index)
      on_exit(fn -> ServerVariables.put(index, original) end)

      quest = %{
        context.quest
        | required_skill: 0,
          required_condition_id: 1,
          required_condition: %Condition{type: :saved_variable, value1: index, value2: 1, value3: 0}
      }

      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      state = context.state |> QuestGivers.enter() |> sync_and_deliver(context.guid, 0)
      ServerVariables.put(index, 1)
      assert_receive {:server_variable_changed, ^index}
      {:noreply, state} = PlayerServer.handle_info({:server_variable_changed, index}, state)
      state = deliver(state, context.guid, 5)
      ServerVariables.put(index, 1)
      refute_received {:server_variable_changed, ^index}
      QuestGivers.leave(state)
      ServerVariables.put(index, 0)
      refute_receive {:server_variable_changed, ^index}
    end

    test "re-evaluates visible givers only when the viewer's eligibility changes", context do
      state = sync_and_deliver(context.state, context.guid, 0)
      assert QuestGivers.sync(state) == state
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}

      player = %{state.character.player | skills: %{185 => %{value: 50}}}
      state = sync_and_deliver(%{state | character: %{state.character | player: player}}, context.guid, 5)
      assert state.questgiver_statuses == %{context.guid => 5}
    end
  end

  describe "timeout/2" do
    test "time gates schedule truth boundaries and reject stale callbacks", context do
      assert Watch.next_delay(%Watch{minutes: [12 * 60, 13 * 60 + 1]}, ~N[2026-09-30 11:59:30]) == 30_000
      assert Watch.next_delay(%Watch{minutes: [12 * 60, 13 * 60 + 1]}, ~N[2026-09-30 12:00:00]) == 3_660_000
      assert Watch.next_delay(%Watch{minutes: [0]}, ~N[2026-09-30 23:59:59]) == 1_000
      assert Watch.next_delay(%Watch{}, ~N[2026-09-30 12:00:00]) == nil

      quest = %{
        context.quest
        | required_skill: 0,
          required_condition_id: 1,
          required_condition: %Condition{type: :local_time, value1: 0, value3: 23, value4: 59}
      }

      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      state = sync_and_deliver(context.state, context.guid, 5)
      ref = state.quest_refresh
      assert is_reference(ref)
      assert QuestGivers.timeout(state, make_ref()) == state
      left = state |> QuestGivers.enter() |> QuestGivers.leave()
      assert left.quest_refresh == nil
      assert :erlang.read_timer(ref) == false
    end
  end

  describe "enter/1" do
    test "subscribes the viewer to game events and its world's facts until it leaves", context do
      saved = GameEvent.get_events()
      on_exit(fn -> GameEvent.set_events(saved) end)
      world = context.state.character.internal.world
      state = QuestGivers.enter(context.state)
      assert state.world_facts_key == Topics.world_facts(world)

      Topics.publish(Topics.world_facts(world), {:world_facts_changed, world})
      assert_receive {:world_facts_changed, ^world}
      GameEvent.set_events([context.quest.id | saved])
      assert_receive {:game_events_changed, _active}

      other = WorldRef.open(1)

      moved =
        QuestGivers.enter(%{
          state
          | character: %{state.character | internal: %{state.character.internal | world: other}}
        })

      assert moved.world_facts_key == Topics.world_facts(other)
      Topics.publish(Topics.world_facts(world), {:world_facts_changed, world})
      refute_receive {:world_facts_changed, ^world}, 50

      left = QuestGivers.leave(moved)
      assert left.world_facts_key == nil
      GameEvent.set_events(saved)
      refute_receive {:game_events_changed, _active}, 50
    end

    test "a published world event refreshes a stationary viewer", context do
      saved = GameEvent.get_events()
      on_exit(fn -> GameEvent.set_events(saved) end)
      quest = %{context.quest | required_skill: 0, event_id: context.quest.id}
      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      state = context.state |> QuestGivers.enter() |> sync_and_deliver(context.guid, 0)

      GameEvent.set_events([quest.event_id | saved])
      assert_receive {:game_events_changed, _active} = message
      assert {:noreply, _state} = PlayerServer.handle_info(message, state)
      assert_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{guid: guid, status: 5}, _opts}}
      assert guid == context.guid
    end
  end

  describe "remember/2" do
    test "shares the status cache with ordinary client query responses", context do
      packet = %SmsgQuestgiverStatus{guid: context.guid, status: 0}
      state = PacketSink.send(context.state, packet)
      assert_received {:"$gen_cast", {:write_packet, _}}
      assert state.questgiver_statuses == %{context.guid => 0}
      QuestGivers.refresh(state)
      refute_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{}, _}}
      removed = Visibility.untrack_entity(state, context.guid)
      assert QuestGivers.remember(removed, packet) == removed
    end
  end

  defp refresh_and_deliver(state, guid, status), do: deliver(QuestGivers.refresh(state), guid, status)

  defp sync_and_deliver(state, guid, status), do: deliver(QuestGivers.sync(state), guid, status)

  defp deliver(state, guid, status) do
    assert_received {:"$gen_cast", {:send_packet, %SmsgQuestgiverStatus{guid: ^guid, status: ^status} = packet, opts}}
    assert opts == [source_guid: guid]
    state = PacketSink.send(state, packet, opts)

    assert_received {:"$gen_cast",
                     {:write_packet, %Packet{payload: <<^guid::little-size(64), ^status::little-size(32)>>}}}

    state
  end

  defp questgiver(_context) do
    QuestLoader.init()
    ReputationLoader.init()
    id = System.unique_integer([:positive, :monotonic])
    entry = 4_000_000 + id
    guid = Guid.from_low_guid(:mob, entry, id)
    quest = %Quest{id: entry, required_skill: 185, required_skill_value: 50}
    :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
    :ets.insert(QuestLoader, {{:giver, entry}, [quest.id]})

    character = %Character{
      id: id,
      object: %Object{guid: id},
      unit: %Unit{race: 1, class: 1, level: 50, health: 100, max_health: 100},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    npc = %{object: %Object{guid: guid}, internal: character.internal, movement_block: character.movement_block}
    Entity.register(guid)
    World.update_position(npc, :mobs)
    Metadata.put(guid, %{alive?: true, npc_flags: 2})

    on_exit(fn ->
      :ets.delete(QuestLoader, {:quest, quest.id})
      :ets.delete(QuestLoader, {:giver, entry})
      Metadata.delete(guid)
      World.remove_position(npc, :mobs)
    end)

    %{
      guid: guid,
      quest: quest,
      state: %State{
        guid: id,
        character: character,
        connection_pid: self(),
        ready: true,
        tracked_entities: MapSet.new([guid])
      }
    }
  end
end
