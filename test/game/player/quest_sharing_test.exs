defmodule ThistleTea.Game.Player.QuestSharingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestSharing.Offer
  alias ThistleTea.Game.Entity.Registry
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.QuestSharing
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:party]

  describe "share/2" do
    test "offers only a current shareable quest to online group members", %{source: source, quest: quest} do
      assert QuestSharing.share(source, quest.id) == source
      assert_receive {:"$gen_cast", {:quest_share, _, _, :manual}}
      assert_receive {:"$gen_cast", {:quest_share, _, _, :manual}}
      QuestSharing.share(source, quest.id + 99)
      put_quest(%{quest | flags: 0})
      QuestSharing.share(source, quest.id)
      QuestSharing.share(%{source | ready: false}, quest.id)
      refute_receive {:"$gen_cast", {:quest_share, _, _, _}}
    end
  end

  describe "receive_offer/4" do
    test "presents player-sourced details and preserves a busy offer", context do
      state = offer(context)
      assert %Offer{quest_id: quest_id, mode: :manual} = state.quest_share
      assert quest_id == context.quest.id
      assert_result(0)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestDetails{npc_guid: sharer}}}
      assert sharer == context.source.guid
      assert QuestSharing.receive_offer(state, sharer, quest_id, :manual) == state
      assert_result(0)
      assert_result(5)
      QuestSharing.clear(state)
    end

    test "reports range, world, completion, and full-log failures", context do
      target = relocate(context.target, 14.0)
      assert QuestSharing.receive_offer(target, context.source.guid, context.quest.id, :manual) == target
      assert_result(0)
      assert_result(4)
      target = relocate(target, 1.0, WorldRef.open(1))
      QuestSharing.receive_offer(target, context.source.guid, context.quest.id, :manual)
      assert_result(0)
      assert_result(4)
      target = relocate(target, 1.0)
      {:ok, log} = QuestLog.add(%{}, context.quest.id)
      {:ok, log} = QuestLog.update(log, context.quest.id, &%{&1 | status: :complete})
      complete = put_log(target, log)
      QuestSharing.receive_offer(complete, context.source.guid, context.quest.id, :manual)
      assert_result(0)
      assert_result(8)

      full =
        Enum.reduce(1..20, %{}, fn id, log ->
          {:ok, next} = QuestLog.add(log, id)
          next
        end)

      QuestSharing.receive_offer(put_log(target, full), context.source.guid, context.quest.id, :manual)
      assert_result(0)
      assert_result(6)
    end
  end

  describe "accept/3" do
    test "requires the matching offer and rechecks current distance and conditions", context do
      assert Quests.accept(context.target, context.source.guid, context.quest.id) == context.target
      state = offer(context)
      assert Quests.accept(state, context.other.guid, context.quest.id) == state
      far = relocate(state, 15.0)
      rejected = Quests.accept(far, context.source.guid, context.quest.id)
      assert rejected.quest_share == nil
      refute QuestLog.active?(rejected.character.player.quest_log, context.quest.id)
      assert_result(4)
      state = offer(%{context | target: relocate(context.target, 1.0)})
      condition = %Condition{entry: 999, type: :level, value1: 60, value2: 0}
      put_quest(%{context.quest | required_condition_id: 999, required_condition: condition})
      rejected = Quests.accept(state, context.source.guid, context.quest.id)
      assert rejected.quest_share == nil
      refute QuestLog.active?(rejected.character.player.quest_log, context.quest.id)
      assert_result(1)
    end

    test "uses ordinary source-item grants and the sharer's remaining timer", context do
      quest = put_quest(%{context.quest | src_item_id: context.item.entry, src_item_count: 2, limit_time: 60})
      {:ok, log} = QuestLog.add(%{}, quest, Time.now() - 20_000, System.system_time(:second) - 20)
      source = put_log(context.source, log)
      state = offer(%{context | source: source})
      accepted = Quests.accept(state, source.guid, quest.id)
      assert accepted.quest_share == nil
      assert accepted.quest_share_monitor == nil
      assert QuestLog.get(accepted.character.player.quest_log, quest.id).expires_at_ms == log[0].expires_at_ms
      assert Inventory.count_entry(accepted.character.player, context.item.entry, &ItemStore.get/1) == 2
      assert CharacterStore.get(accepted.guid).player.quest_log == accepted.character.player.quest_log
      assert_result(2)
      assert Quests.accept(accepted, source.guid, quest.id) == accepted
      refute_receive {:"$gen_cast", {:send_packet, %Message.MsgQuestPushResult{result: 2}}}
    end

    test "does not add a quest or acknowledge acceptance when source items cannot fit", context do
      quest = put_quest(%{context.quest | src_item_id: context.item.entry})

      fields =
        Map.new(1..16, fn index ->
          filler = ItemStore.create(context.item, owner: context.target.guid, stack_count: 20)
          {String.to_atom("inv#{index}"), filler.object.guid}
        end)

      player = struct!(context.target.character.player, fields)
      target = %{context.target | character: %{context.target.character | player: player}}
      state = offer(%{context | target: target})
      rejected = Quests.accept(state, context.source.guid, quest.id)
      refute QuestLog.active?(rejected.character.player.quest_log, quest.id)
      assert rejected.quest_share == nil
      assert_result(1)
      refute_receive {:"$gen_cast", {:send_packet, %Message.MsgQuestPushResult{result: 2}}}
    end
  end

  describe "confirm/2" do
    test "NPC acceptance prompts eligible members without repeating the start script", context do
      quest = put_quest(%{context.quest | flags: 2, start_script_steps: [%ScriptStep{command: :talk}]})
      source = put_log(context.source, %{})
      npc = Guid.from_low_guid(:mob, quest.id, 1)
      Registry.register(npc)
      :ets.insert(QuestLoader, {{:giver, quest.id}, [quest.id]})
      on_exit(fn -> :ets.delete(QuestLoader, {:giver, quest.id}) end)
      source = Quests.accept(source, npc, quest.id)
      assert QuestLog.active?(source.character.player.quest_log, quest.id)
      assert_receive {:"$gen_cast", {:start_script, _, _}}
      assert_receive {:"$gen_cast", {:quest_share, _, _, :party_accept}}
      target = QuestSharing.receive_offer(context.target, source.guid, quest.id, :party_accept)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestConfirmAccept{quest_id: id}}}
      assert id == quest.id
      accepted = QuestSharing.confirm(target, quest.id)
      assert QuestLog.active?(accepted.character.player.quest_log, quest.id)
      assert accepted.quest_share == nil
      refute_receive {:"$gen_cast", {:start_script, _, _}}
    end

    test "enforces ordinary subgroups and allows raid quest confirmations", context do
      quest = put_quest(%{context.quest | flags: 2})
      {:ok, _} = PartySystem.convert_raid(context.source.guid)
      {:ok, _} = PartySystem.change_subgroup(context.source.guid, context.target.guid, 1)
      assert QuestSharing.receive_offer(context.target, context.source.guid, quest.id, :party_accept) == context.target
      quest = put_quest(%{quest | type: 62})
      target = QuestSharing.receive_offer(context.target, context.source.guid, quest.id, :party_accept)
      assert %Offer{} = target.quest_share
      accepted = QuestSharing.confirm(target, quest.id)
      assert QuestLog.active?(accepted.character.player.quest_log, quest.id)
    end
  end

  describe "offer cleanup" do
    test "declines only the pending offer and ignores claimed client acceptance", context do
      state = offer(context)
      assert QuestSharing.result(state, 2) == state
      refute_receive {:"$gen_cast", {:send_packet, %Message.MsgQuestPushResult{result: 2}}}

      declined =
        Message.MsgQuestPushResultClient.handle(
          %Message.MsgQuestPushResultClient{guid: context.other.guid, result: 3},
          state
        )

      assert declined.quest_share == nil
      assert_result(3)
      refute QuestLog.active?(declined.character.player.quest_log, context.quest.id)
      assert QuestSharing.result(declined, 3) == declined
    end

    test "invalidates abandoned quests and changed group membership", context do
      state = offer(context)
      Quests.abandon(context.source, 0)
      assert_receive {:"$gen_cast", {:cancel_quest_share, sharer, quest_id}}
      assert QuestSharing.cancel(state, sharer, quest_id).quest_share == nil
      state = offer(%{context | source: put_log(context.source, context.source.character.player.quest_log)})
      {:ok, _} = PartySystem.leave(context.target.guid)
      assert QuestSharing.refresh(state).quest_share == nil

      refute QuestLog.active?(
               Quests.accept(state, context.source.guid, context.quest.id).character.player.quest_log,
               context.quest.id
             )
    end

    test "monitors the sharer's owner and rejects old sessions", context do
      Registry.unregister(context.source.guid)
      parent = self()

      pid =
        spawn(fn ->
          Registry.register(context.source.guid)
          send(parent, :registered)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :registered
      state = offer(context)
      send(pid, :stop)
      assert_receive {:DOWN, monitor, :process, ^pid, reason}
      assert {:noreply, cleared} = PlayerServer.handle_info({:DOWN, monitor, :process, pid, reason}, state)
      assert cleared.quest_share == nil
      Registry.register(context.source.guid)
      assert QuestSharing.refresh(state).quest_share == nil

      refute QuestLog.active?(
               Quests.accept(state, context.source.guid, context.quest.id).character.player.quest_log,
               context.quest.id
             )
    end
  end

  defp assert_result(result) do
    assert_receive {:"$gen_cast", {:send_packet, %Message.MsgQuestPushResult{result: ^result}}}
  end

  defp offer(context) do
    QuestSharing.receive_offer(context.target, context.source.guid, context.quest.id, :manual)
  end

  defp put_quest(quest) do
    :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
    quest
  end

  defp put_log(state, log) do
    character = %{state.character | player: %{state.character.player | quest_log: log}}
    CharacterStore.put(character)
    %{state | character: character}
  end

  defp relocate(state, x, world \\ WorldRef.open(0)) do
    character = %{
      state.character
      | movement_block: %{state.character.movement_block | position: {x, 0.0, 0.0, 0.0}},
        internal: %{state.character.internal | world: world}
    }

    Presence.relocate(character)
    %{state | character: character}
  end

  defp party(_context) do
    source = character("Sharer", 0.0)
    target = character("Recipient", 5.0)
    other = character("Witness", 10.0)
    quest = put_quest(%Quest{id: 950_000 + source.guid, flags: 8, min_level: 10, required_kills: [{0, 299, 2}]})
    item = %ItemTemplate{entry: quest.id, name: "Quest Source", stackable: 20}
    :ets.insert(ItemLoader, {item.entry, item})
    {:ok, log} = QuestLog.add(%{}, quest.id)
    source = put_log(source, log)

    for state <- [source, target, other] do
      Registry.register(state.guid)
      CharacterStore.put(state.character)
      Presence.enter(state.character, %{level: 50, class: 1, race: 1})
    end

    :ok = PartySystem.invite(source.guid, "Sharer", target.guid)
    {:ok, _} = PartySystem.accept(target.guid, "Recipient")
    :ok = PartySystem.invite(source.guid, "Sharer", other.guid)
    {:ok, _} = PartySystem.accept(other.guid, "Witness")

    on_exit(fn ->
      for state <- [source, target, other] do
        PartySystem.leave(state.guid)
        Presence.leave(state.character)
        :ets.delete(CharacterStore, state.guid)
      end

      :ets.delete(QuestLoader, {:quest, quest.id})
      :ets.delete(ItemLoader, item.entry)

      for {guid, %{item: %{owner: owner}}} <- :ets.tab2list(ItemStore), owner == target.guid do
        ItemStore.delete(guid)
      end
    end)

    %{source: source, target: target, other: other, quest: quest, item: item}
  end

  defp character(name, x) do
    guid = System.unique_integer([:positive, :monotonic])

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{race: 1, class: 1, level: 50, health: 100, max_health: 100},
      player: %Player{},
      internal: %Internal{name: name, world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}}
    }

    %State{guid: guid, character: character, ready: true}
  end
end
