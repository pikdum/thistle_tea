defmodule ThistleTea.Game.Player.QuestItemProgressTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  @quest_id 3904
  @item_id 11_119

  setup do
    ItemStore.init()
    QuestLoader.init()

    quest = %Quest{id: @quest_id, required_items: [{0, @item_id, 8}]}
    :ets.insert(QuestLoader, {{:quest, @quest_id}, quest})
    on_exit(fn -> :ets.delete(QuestLoader, {:quest, @quest_id}) end)

    {:ok, quest_log} = QuestLog.add(%{}, @quest_id)
    player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))

    character = %Character{
      object: %Object{guid: player_guid},
      unit: %Unit{race: 1, class: 8, level: 1, health: 50, max_health: 50},
      player: %Player{quest_log: quest_log},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{map: 0}
    }

    {:ok, character: character, player_guid: player_guid}
  end

  defp grape_template, do: %ItemTemplate{entry: @item_id, name: "Milly's Harvest", stackable: 20}

  test "first quest item reports the added delta before the bag update", %{
    character: character,
    player_guid: player_guid
  } do
    item = ItemStore.create(grape_template(), owner: player_guid)
    on_exit(fn -> ItemStore.delete(item.object.guid) end)

    player = %{character.player | inv1: item.object.guid}
    state = %{character: character, guid: player_guid}

    InventoryUpdate.apply(state, {:ok, %{player: player, items: [item], destroyed: []}})

    assert_received {:"$gen_cast",
                     {:send_packet, %Message.SmsgQuestupdateAddItem{item_id: @item_id, count: 1} = _progress}}
  end

  test "merging into an existing stack still reports the delta", %{
    character: character,
    player_guid: player_guid
  } do
    stack = ItemStore.create(grape_template(), owner: player_guid, stack_count: 2)
    on_exit(fn -> ItemStore.delete(stack.object.guid) end)

    character = %{character | player: %{character.player | inv1: stack.object.guid}}
    state = %{character: character, guid: player_guid}

    merged = %{stack | item: %{stack.item | stack_count: 3}}

    InventoryUpdate.apply(state, {:ok, %{player: character.player, items: [merged], destroyed: []}})

    assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestupdateAddItem{item_id: @item_id, count: 1}}}
    assert ItemStore.get(stack.object.guid).item.stack_count == 3
  end

  test "quest_item_counts snapshots current counts", %{character: character, player_guid: player_guid} do
    stack = ItemStore.create(grape_template(), owner: player_guid, stack_count: 5)
    on_exit(fn -> ItemStore.delete(stack.object.guid) end)

    character = %{character | player: %{character.player | inv1: stack.object.guid}}

    assert Quests.quest_item_counts(character) == %{@item_id => 5}
  end
end
