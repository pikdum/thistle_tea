defmodule ThistleTea.Game.World.Visibility.QuestGiversTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestGraph
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgQuestgiverStatus
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.World.Visibility.QuestGivers
  alias ThistleTea.Game.WorldRef

  setup [:questgiver]

  describe "refresh/1" do
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
      assert QuestGivers.refresh(removed) == removed
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

  defp refresh_and_deliver(state, guid, status) do
    state = QuestGivers.refresh(state)
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
