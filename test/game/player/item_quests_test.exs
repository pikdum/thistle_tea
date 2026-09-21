defmodule ThistleTea.Game.Player.ItemQuestsTest do
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
  alias ThistleTea.Game.Entity.Registry
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:quest_items]

  describe "cancel_dialog/1" do
    test "dispatches an empty cancel request without consuming the starter", context do
      packet = %Packet{opcode: Opcodes.get(:CMSG_QUESTGIVER_CANCEL), payload: <<>>}
      assert %Message.CmsgQuestgiverCancel{} = message = Dispatch.to_message(packet)
      assert Message.handle(message, context.state) == context.state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}
      assert ItemStore.get(context.item.object.guid) == context.item
      assert context.state.character.player.quest_log == %{}
      not_ready = %{context.state | ready: false}
      assert Message.handle(message, not_ready) == not_ready
      refute_receive {:"$gen_cast", {:send_packet, _}}
    end
  end

  describe "query_quest/3" do
    test "opens an owned item's quest through the registered client codec", context do
      payload = <<context.item.object.guid::little-size(64), context.quest.id::little-size(32)>>
      packet = %Packet{opcode: Opcodes.get(:CMSG_QUESTGIVER_QUERY_QUEST), payload: payload}
      assert %Message.CmsgQuestgiverQueryQuest{} = message = Dispatch.to_message(packet)
      assert Message.handle(message, context.state) == context.state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestDetails{npc_guid: guid, quest: quest}}}
      assert guid == context.item.object.guid
      assert quest == context.quest
      assert ItemStore.get(guid) == context.item
      refute QuestLog.active?(context.state.character.player.quest_log, quest.id)
    end

    test "rejects unowned, detached, and mismatched item references", context do
      foreign = %{context.item | item: %{context.item.item | owner: context.state.guid + 1}}
      ItemStore.put(foreign)
      Quests.query_quest(context.state, foreign.object.guid, context.quest.id)
      ItemStore.put(context.item)
      Quests.query_quest(put_player(context.state, %Player{}), context.item.object.guid, context.quest.id)
      Quests.query_quest(context.state, context.item.object.guid, context.quest.id + 1)

      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestDetails{}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}
    end
  end

  describe "accept/3" do
    test "atomically replaces a starter and restores it on abandonment", context do
      accepted = accept(context)
      assert QuestLog.get(accepted.character.player.quest_log, context.quest.id).status == :complete
      assert ItemStore.get(context.item.object.guid) == nil
      assert count(accepted, context.source.entry) == 1
      assert count(accepted, context.starter.entry) == 0
      assert CharacterStore.get(accepted.guid).player == accepted.character.player
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemPushResult{item_id: entry, count: 1}}}
      assert entry == context.source.entry
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}

      abandoned = Quests.abandon(accepted, 0)
      assert count(abandoned, context.source.entry) == 0
      assert count(abandoned, context.starter.entry) == 1
      refute QuestLog.active?(abandoned.character.player.quest_log, context.quest.id)

      restored =
        Enum.find(
          Inventory.owned_items(abandoned.character.player, &ItemStore.get/1),
          &(&1.object.entry == context.starter.entry)
        )

      assert restored.object.guid != context.item.object.guid
      assert count(Quests.accept(abandoned, restored.object.guid, context.quest.id), context.source.entry) == 1
    end

    test "preserves starters needed for the source item without duplicate grants", context do
      quest =
        put_quest(%{
          context.quest
          | src_item_id: context.starter.entry,
            required_items: [{0, context.starter.entry, 1}]
        })

      accepted = accept(%{context | quest: quest})
      assert QuestLog.get(accepted.character.player.quest_log, quest.id).status == :complete
      assert ItemStore.get(context.item.object.guid) == context.item
      assert count(accepted, context.starter.entry) == 1
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemPushResult{}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{}}}
    end

    test "preserves an objective starter even when no source item is configured", context do
      quest = put_quest(%{context.quest | src_item_id: 0, required_items: [{0, context.starter.entry, 1}]})
      accepted = accept(%{context | quest: quest})
      assert QuestLog.get(accepted.character.player.quest_log, quest.id).status == :complete
      assert ItemStore.get(context.item.object.guid) == context.item
      assert count(accepted, context.starter.entry) == 1
    end

    test "rechecks existence and ownership after presenting details", context do
      Quests.query_quest(context.state, context.item.object.guid, context.quest.id)
      ItemStore.delete(context.item.object.guid)
      assert accept(context) == context.state
      ItemStore.put(%{context.item | item: %{context.item.item | owner: context.state.guid + 1}})
      assert accept(context) == context.state
      ItemStore.put(context.item)
      detached = put_player(context.state, %Player{})
      assert accept(%{context | state: detached}) == detached
      assert CharacterStore.get(context.state.guid).player.quest_log == %{}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemPushResult{}}}
    end

    test "rejects replay without consuming another copy", context do
      duplicate = ItemStore.create(context.starter, owner: context.state.guid)
      state = put_player(context.state, %{context.state.character.player | inv2: duplicate.object.guid})
      accepted = accept(%{context | state: state})
      assert Quests.accept(accepted, duplicate.object.guid, context.quest.id) == accepted
      assert ItemStore.get(duplicate.object.guid) == duplicate
      assert count(accepted, context.source.entry) == 1
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestInvalid{reason: 13}}}
    end

    test "checks source capacity before consuming a starter and allows retry", context do
      full = fill_backpack(context)
      assert accept(%{context | state: full}) == full
      assert ItemStore.get(context.item.object.guid) == context.item
      assert count(full, context.source.entry) == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 50}}}

      available = put_player(full, %{full.character.player | inv16: 0})
      accepted = accept(%{context | state: available})
      assert QuestLog.active?(accepted.character.player.quest_log, context.quest.id)
      assert count(accepted, context.source.entry) == 1
      assert ItemStore.get(context.item.object.guid) == nil
    end

    test "rejects full logs and dead players without touching inventory", context do
      log =
        Enum.reduce(1..20, %{}, fn id, log ->
          {:ok, log} = QuestLog.add(log, id)
          log
        end)

      full = put_player(context.state, %{context.state.character.player | quest_log: log})
      assert accept(%{context | state: full}) == full
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestlogFull{}}}

      dead = %{
        context.state
        | character: %{context.state.character | unit: %{context.state.character.unit | health: 0}}
      }

      assert accept(%{context | state: dead}) == dead
      ghost = put_player(context.state, %{context.state.character.player | flags: 0x10})
      assert accept(%{context | state: ghost}) == ghost
      assert ItemStore.get(context.item.object.guid) == context.item
    end

    test "checks requirements and conditions at acceptance", context do
      Quests.query_quest(context.state, context.item.object.guid, context.quest.id)

      for {quest, reason} <- [
            {%{context.quest | min_level: 51}, 0},
            {%{context.quest | required_races: 2}, 6},
            {%{context.quest | required_classes: 2}, 0},
            {%{context.quest | prev_quest_id: 12_345}, 0},
            {%{context.quest | required_skill: 185, required_skill_value: 50}, 0},
            {%{
               context.quest
               | required_condition_id: 1,
                 required_condition: %Condition{entry: 1, type: :item, value1: context.source.entry, value2: 1}
             }, 0}
          ] do
        put_quest(quest)
        assert accept(context) == context.state
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestInvalid{reason: ^reason}}}
      end

      assert ItemStore.get(context.item.object.guid) == context.item
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemPushResult{}}}
    end

    test "accepts from owned bank storage without a world-object script", context do
      Registry.register(context.item.object.guid)
      quest = put_quest(%{context.quest | start_script_steps: [%ScriptStep{command: :talk}]})
      state = put_player(context.state, %Player{bank1: context.item.object.guid})
      accepted = accept(%{context | state: state, quest: quest})
      assert QuestLog.active?(accepted.character.player.quest_log, quest.id)
      assert accepted.character.player.bank1 == 0
      assert count(accepted, context.source.entry) == 1
      refute_receive {:"$gen_cast", {:start_script, _, _}}
    end

    test "prompts group members when an item starts a party-accept quest", context do
      recipient = System.unique_integer([:positive, :monotonic])
      Registry.register(recipient)
      :ok = PartySystem.invite(context.state.guid, "Starter", recipient)
      {:ok, _group} = PartySystem.accept(recipient, "Recipient")

      on_exit(fn ->
        PartySystem.leave(context.state.guid)
        PartySystem.leave(recipient)
      end)

      quest = put_quest(%{context.quest | flags: 2})
      accepted = accept(%{context | quest: quest})
      assert QuestLog.active?(accepted.character.player.quest_log, quest.id)
      assert_receive {:"$gen_cast", {:quest_share, sharer, quest_id, :party_accept}}
      assert sharer == context.state.guid
      assert quest_id == quest.id
    end

    test "keeps other quests' new completion when granting a source item", context do
      other = put_quest(%Quest{id: context.quest.id + 1, required_items: [{0, context.source.entry, 1}]})
      {:ok, log} = QuestLog.add(%{}, other.id)
      state = put_player(context.state, %{context.state.character.player | quest_log: log})
      accepted = accept(%{context | state: state})
      assert QuestLog.get(accepted.character.player.quest_log, other.id).status == :complete
      assert QuestLog.get(accepted.character.player.quest_log, context.quest.id).status == :complete
    end

    test "keeps other quests' lost completion when consuming their objective item", context do
      other = put_quest(%Quest{id: context.quest.id + 1, required_items: [{0, context.starter.entry, 1}]})
      {:ok, log} = QuestLog.add(%{}, other.id)
      {:ok, log} = QuestLog.update(log, other.id, &%{&1 | status: :complete})
      state = put_player(context.state, %{context.state.character.player | quest_log: log})
      accepted = accept(%{context | state: state})
      assert QuestLog.get(accepted.character.player.quest_log, other.id).status == :incomplete
      assert QuestLog.get(accepted.character.player.quest_log, context.quest.id).status == :complete
    end
  end

  defp accept(context) do
    payload = <<context.item.object.guid::little-size(64), context.quest.id::little-size(32)>>
    message = Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_QUESTGIVER_ACCEPT_QUEST), payload: payload})
    Message.handle(message, context.state)
  end

  defp count(state, entry), do: Inventory.count_entry_with_bank(state.character.player, entry, &ItemStore.get/1)

  defp put_player(state, player), do: %{state | character: %{state.character | player: player}}

  defp put_quest(quest) do
    :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
    quest
  end

  defp fill_backpack(context) do
    player =
      Enum.reduce(2..16, context.state.character.player, fn index, player ->
        item = ItemStore.create(%ItemTemplate{entry: context.source.entry + index}, owner: context.state.guid)
        struct!(player, [{String.to_atom("inv#{index}"), item.object.guid}])
      end)

    put_player(context.state, player)
  end

  defp quest_items(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    quest_id = 2_000_000 + guid * 10
    starter = %ItemTemplate{entry: quest_id + 1, name: "Quest Starter", start_quest: quest_id, bonding: 1}
    source = %ItemTemplate{entry: quest_id + 2, name: "Quest Source", bonding: 4}
    Enum.each([starter, source], &:ets.insert(ItemLoader, {&1.entry, &1}))

    quest =
      put_quest(%Quest{
        id: quest_id,
        src_item_id: source.entry,
        src_item_count: 1,
        required_items: [{0, source.entry, 1}],
        start_item_template: starter
      })

    item = ItemStore.create(starter, owner: guid)

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{race: 1, class: 1, level: 50, health: 100, max_health: 100},
      player: %Player{inv1: item.object.guid},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      Enum.each([starter, source], &:ets.delete(ItemLoader, &1.entry))
      Enum.each([quest_id, quest_id + 1], &:ets.delete(QuestLoader, {:quest, &1}))
      :ets.delete(CharacterStore, guid)
      Metadata.delete(guid)
      ItemStore.delete(item.object.guid)

      for {item_guid, %{item: %{owner: ^guid}}} <- :ets.tab2list(ItemStore) do
        ItemStore.delete(item_guid)
      end
    end)

    %{
      state: %State{guid: guid, character: character, ready: true},
      quest: quest,
      item: item,
      starter: starter,
      source: source
    }
  end
end
