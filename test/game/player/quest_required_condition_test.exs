defmodule ThistleTea.Game.Player.QuestRequiredConditionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.QuestItem
  alias ThistleTea.Game.Player.Gossip
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup do
    CharacterStore.init()
    GossipLoader.init()
    ItemLoader.init()
    ItemStore.init()
    QuestLoader.init()
    ReputationLoader.init()

    id = System.unique_integer([:positive, :monotonic])
    quest_id = 900_000 + id * 10
    npc_entry = 800_000 + id
    player_guid = Guid.from_low_guid(:player, id)
    npc_guid = Guid.from_low_guid(:mob, npc_entry, id)
    item_id = 10_575
    source_item_id = 700_000 + id
    character = character(id, player_guid)
    CharacterStore.put(character)

    on_exit(fn ->
      Enum.each(0..5, &:ets.delete(QuestLoader, {:quest, quest_id + &1}))
      :ets.delete(QuestLoader, {:giver, npc_entry})
      :ets.delete(QuestLoader, {:ender, npc_entry})
      :ets.delete(GossipLoader, {:creature_menu, npc_entry})
      :ets.delete(CharacterStore, id)
      Metadata.delete(player_guid)
      Metadata.delete(npc_guid)
      delete_owned_items(player_guid)
    end)

    {:ok,
     character: character,
     id: id,
     item_id: item_id,
     source_item_id: source_item_id,
     npc_entry: npc_entry,
     npc_guid: npc_guid,
     player_guid: player_guid,
     quest_id: quest_id}
  end

  test "status, native hello, and gossip share conditioned visibility", context do
    quest = conditioned_quest(context, %Condition{entry: 1, type: :item_with_bank, value1: context.item_id, value2: 1})
    put_quest(context, quest, giver: true)

    assert Quests.dialog_status(context.npc_guid, context.character) == QuestDialogStatus.none()
    assert Quests.quest_menu(context.npc_guid, context.character) == []
    assert Gossip.quest_items(context.npc_guid, context.character) == []

    banked = bank_item(context, context.character)

    assert Quests.dialog_status(context.npc_guid, banked) == QuestDialogStatus.available()
    assert [{^quest, _icon}] = Quests.quest_menu(context.npc_guid, banked)
    assert [%QuestItem{quest_id: quest_id}] = Gossip.quest_items(context.npc_guid, banked)
    assert quest_id == context.quest_id

    Quests.hello(state(context, banked), context.npc_guid)
    assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestDetails{quest: ^quest}}}

    Gossip.hello(state(context, banked), context.npc_guid)
    assert_received {:"$gen_cast", {:send_packet, %Message.SmsgGossipMessage{quests: [_quest]}}}
  end

  test "acceptance re-evaluates a stale bank-backed menu before mutation", context do
    source_item_id = context.source_item_id
    :ets.insert(ItemLoader, {source_item_id, %ItemTemplate{entry: source_item_id, name: "Source"}})
    on_exit(fn -> :ets.delete(ItemLoader, source_item_id) end)

    quest =
      conditioned_quest(
        context,
        %Condition{entry: 1, type: :item_with_bank, value1: context.item_id, value2: 1},
        src_item_id: source_item_id,
        limit_time: 60,
        start_script_steps: [%ScriptStep{command: :talk}]
      )

    put_quest(context, quest, giver: true)
    assert {:ok, _owner} = Entity.register(context.npc_guid)
    on_exit(fn -> Entity.unregister(context.npc_guid) end)
    banked = bank_item(context, context.character)
    assert [{^quest, _icon}] = Quests.quest_menu(context.npc_guid, banked)

    current = %{banked | player: %{banked.player | bank1: nil}}
    CharacterStore.put(current)
    state = state(context, current)

    assert Quests.accept(state, context.npc_guid, quest.id) == state
    refute QuestLog.active?(state.character.player.quest_log, quest.id)
    assert CharacterStore.get(context.id) == current
    refute owned_entry?(context.player_guid, source_item_id)

    assert [%Message.SmsgQuestgiverQuestInvalid{reason: 0}] = sent_packets()
    refute_receive {:"$gen_cast", {:start_script, _steps, _target_guid}}
    refute_receive {:quest_timer_expired, _, _}
  end

  test "unknown acceptance fails closed with one generic invalid packet", context do
    quest = conditioned_quest(context, %Condition{entry: 42, type: :instance_data, value1: 7})
    put_quest(context, quest, giver: true)
    state = state(context, context.character)

    assert Quests.dialog_status(context.npc_guid, context.character) == QuestDialogStatus.none()
    assert Quests.accept(state, context.npc_guid, quest.id) == state
    refute QuestLog.active?(state.character.player.quest_log, quest.id)
    assert [%Message.SmsgQuestgiverQuestInvalid{reason: 0}] = sent_packets()
  end

  test "met acceptance uses the normal transition and force acceptance still bypasses", context do
    quest = conditioned_quest(context, %Condition{entry: 1, type: :item_with_bank, value1: context.item_id, value2: 1})
    put_quest(context, quest, giver: true)

    banked = bank_item(context, context.character)
    accepted = Quests.accept(state(context, banked), context.npc_guid, quest.id)
    assert QuestLog.active?(accepted.character.player.quest_log, quest.id)

    second = %{quest | id: quest.id + 1}
    :ets.insert(QuestLoader, {{:quest, second.id}, second})
    forced = Quests.force_accept(state(context, context.character), second.id)
    assert QuestLog.active?(forced.character.player.quest_log, second.id)
  end

  test "base and purchased bank bags count but carried-only ITEM does not", context do
    bank_condition = %Condition{entry: 1, type: :item_with_bank, value1: context.item_id, value2: 1}
    carried_condition = %Condition{entry: 2, type: :item, value1: context.item_id, value2: 1}
    bank_quest = conditioned_quest(context, bank_condition)
    carried_quest = %{conditioned_quest(context, carried_condition) | id: context.quest_id + 1}

    base_banked = bank_item(context, context.character)
    availability = Quests.availability(base_banked, [bank_quest, carried_quest])
    assert availability.condition_results == %{bank_quest.id => :met, carried_quest.id => :unmet}

    purchased_banked = purchased_bank_item(context, context.character)
    availability = Quests.availability(purchased_banked, [bank_quest, carried_quest])
    assert availability.condition_results == %{bank_quest.id => :met, carried_quest.id => :unmet}

    removed = %{purchased_banked | player: %{purchased_banked.player | bank_bag1: nil, bank_bag_slots: 0}}
    assert Quests.availability(removed, [bank_quest]).condition_results == %{bank_quest.id => :unmet}
  end

  test "map event conditions use the scripted event boundary with a nil source", context do
    quest = %Quest{
      id: 4_463,
      title: "Libram of Rumination",
      required_condition_id: 4_463,
      required_condition: %Condition{entry: 4_463, type: :map_event_active, value1: 4_463}
    }

    assert Quests.availability(context.character, [quest]).condition_results == %{quest.id => :unmet}
  end

  test "active ender and reward flows ignore an unknown start condition", context do
    quest = conditioned_quest(context, %Condition{entry: 42, type: :instance_data, value1: 7})
    put_quest(context, quest, giver: true, ender: true)
    completed = completed_character(context.character, quest.id)
    state = state(context, completed)

    assert [{^quest, icon}] = Quests.quest_menu(context.npc_guid, completed)
    assert icon == QuestDialogStatus.reward_rep()

    assert Quests.complete_quest(state, context.npc_guid, quest.id) == state
    assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverOfferReward{quest: ^quest}}}

    assert Quests.request_reward(state, context.npc_guid, quest.id) == state
    assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverOfferReward{quest: ^quest}}}

    turned_in = Quests.choose_reward(state, context.npc_guid, quest.id, 0)
    refute QuestLog.active?(turned_in.character.player.quest_log, quest.id)
  end

  test "next quest offers apply the same condition gate", context do
    current = %Quest{id: context.quest_id, next_quest_in_chain: context.quest_id + 1}

    next =
      %Quest{
        id: context.quest_id + 1,
        required_condition_id: 1,
        required_condition: %Condition{entry: 1, type: :item_with_bank, value1: context.item_id, value2: 1}
      }

    put_quest(context, current, ender: true)
    :ets.insert(QuestLoader, {{:quest, next.id}, next})
    :ets.insert(QuestLoader, {{:giver, context.npc_entry}, [next.id]})

    turned_in =
      Quests.choose_reward(
        state(context, completed_character(context.character, current.id)),
        context.npc_guid,
        current.id,
        0
      )

    refute QuestLog.active?(turned_in.character.player.quest_log, current.id)

    refute Enum.any?(sent_packets(), fn
             %Message.SmsgQuestgiverQuestDetails{quest: %Quest{id: id}} -> id == next.id
             _packet -> false
           end)
  end

  test "direct details remain relation-only but cannot authorize acceptance", context do
    quest = conditioned_quest(context, %Condition{entry: 1, type: :item_with_bank, value1: context.item_id, value2: 1})
    put_quest(context, quest, giver: true)
    state = state(context, context.character)

    assert Quests.query_quest(state, context.npc_guid, quest.id) == state
    assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestDetails{quest: ^quest}}}

    assert Quests.accept(state, context.npc_guid, quest.id) == state
    assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestInvalid{reason: 0}}}
    refute QuestLog.active?(state.character.player.quest_log, quest.id)
  end

  defp conditioned_quest(context, condition, overrides \\ []) do
    %Quest{
      id: context.quest_id,
      level: 1,
      required_condition_id: condition.entry,
      required_condition: condition
    }
    |> struct!(overrides)
  end

  defp put_quest(context, quest, options) do
    :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
    if Keyword.get(options, :giver), do: :ets.insert(QuestLoader, {{:giver, context.npc_entry}, [quest.id]})
    if Keyword.get(options, :ender), do: :ets.insert(QuestLoader, {{:ender, context.npc_entry}, [quest.id]})
  end

  defp bank_item(context, character) do
    item = ItemStore.create(%ItemTemplate{entry: context.item_id, name: "Banked"}, owner: context.player_guid)
    %{character | player: %{character.player | bank1: item.object.guid}}
  end

  defp purchased_bank_item(context, character) do
    item = ItemStore.create(%ItemTemplate{entry: context.item_id, name: "Bag Banked"}, owner: context.player_guid)

    bag =
      ItemStore.create(
        %ItemTemplate{entry: context.item_id + 2, name: "Bank Bag", class: 1, inventory_type: 18, container_slots: 6},
        owner: context.player_guid
      )

    bag = put_in(bag.container.slot_1, item.object.guid)
    ItemStore.put(bag)

    %{character | player: %{character.player | bank_bag1: bag.object.guid, bank_bag_slots: 1}}
  end

  defp completed_character(character, quest_id) do
    {:ok, quest_log} = QuestLog.add(%{}, quest_id)
    {:ok, quest_log} = QuestLog.update(quest_log, quest_id, &%{&1 | status: :complete})
    %{character | player: %{character.player | quest_log: quest_log}}
  end

  defp character(id, guid) do
    %Character{
      id: id,
      object: %Object{guid: guid},
      unit: %Unit{race: 1, class: 1, level: 60, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
      player: %Player{
        coinage: 0,
        xp: 0,
        next_level_xp: 0,
        skills: %{},
        quest_log: %{},
        rewarded_quests: MapSet.new(),
        reputation: %Reputation{}
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), area: 0, spellbook: %{}}
    }
  end

  defp state(context, character), do: %{character: character, gossip_menu_options: [], guid: context.player_guid}

  defp sent_packets(acc \\ []) do
    receive do
      {:"$gen_cast", {:send_packet, packet}} -> sent_packets([packet | acc])
      {:"$gen_cast", {:send_packet, packet, _options}} -> sent_packets([packet | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp owned_entry?(owner, entry) do
    ItemStore
    |> :ets.tab2list()
    |> Enum.any?(fn
      {_guid, %{object: %{entry: ^entry}, item: %{owner: ^owner}}} -> true
      _row -> false
    end)
  end

  defp delete_owned_items(owner) do
    ItemStore
    |> :ets.tab2list()
    |> Enum.each(fn
      {guid, %{item: %{owner: ^owner}}} -> ItemStore.delete(guid)
      _row -> :ok
    end)
  end
end
