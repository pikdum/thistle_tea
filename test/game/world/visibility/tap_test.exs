defmodule ThistleTea.Game.World.Visibility.TapTest do
  use ExUnit.Case, async: false

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility.Tap

  @dynamic_flag_lootable 0x0001
  @dynamic_flag_tapped 0x0004
  @quest_id 3904
  @quest_item_id 11_119

  setup do
    ItemStore.init()
    QuestLoader.init()

    :ets.insert(QuestLoader, {{:quest, @quest_id}, %Quest{id: @quest_id, required_items: [{0, @quest_item_id, 8}]}})
    on_exit(fn -> :ets.delete(QuestLoader, {:quest, @quest_id}) end)

    viewer = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
    mob_guid = Guid.from_low_guid(:mob, 299, System.unique_integer([:positive, :monotonic]))
    on_exit(fn -> Metadata.delete(mob_guid) end)

    {:ok, viewer: viewer, mob_guid: mob_guid}
  end

  describe "personalize/3" do
    test "marks the corpse as another player's tap when the only quest drop is unusable", context do
      publish(context, quest_loot())

      flags = personalize(context, character_without_quest())

      assert (flags &&& @dynamic_flag_lootable) == 0
      assert (flags &&& @dynamic_flag_tapped) != 0
    end

    test "keeps the sparkle for a tapper on the quest", context do
      publish(context, quest_loot())

      flags = personalize(context, character_on_quest())

      assert (flags &&& @dynamic_flag_lootable) != 0
      assert (flags &&& @dynamic_flag_tapped) == 0
    end

    test "keeps the sparkle when general loot remains", context do
      publish(context, %Loot{items: [%Loot.Item{slot: 0, item_id: 2589}]})

      flags = personalize(context, character_without_quest())

      assert (flags &&& @dynamic_flag_lootable) != 0
      assert (flags &&& @dynamic_flag_tapped) == 0
    end

    test "keeps the sparkle when only gold remains", context do
      publish(context, %Loot{gold: 42})

      flags = personalize(context, character_without_quest())

      assert (flags &&& @dynamic_flag_lootable) != 0
    end

    test "hides the sparkle from a player who did not tap", context do
      publish(context, %Loot{gold: 42}, tapped_player: context.viewer + 1)

      flags = personalize(context, character_without_quest())

      assert (flags &&& @dynamic_flag_lootable) == 0
      assert (flags &&& @dynamic_flag_tapped) != 0
    end

    test "hides the sparkle from a group member who is not the round-robin looter", context do
      Metadata.put(context.mob_guid, %{
        tapped_player: context.viewer,
        assigned_looter: context.viewer + 1,
        loot_summary: Loot.summary(%Loot{gold: 42})
      })

      flags = personalize(context, character_without_quest())

      assert (flags &&& @dynamic_flag_lootable) == 0
      assert (flags &&& @dynamic_flag_tapped) != 0
    end

    test "leaves the flags alone without a published loot summary", context do
      Metadata.put(context.mob_guid, %{tapped_player: context.viewer})

      flags = personalize(context, character_without_quest())

      assert (flags &&& @dynamic_flag_lootable) != 0
      assert (flags &&& @dynamic_flag_tapped) == 0
    end
  end

  defp publish(%{mob_guid: mob_guid} = context, %Loot{} = loot, opts \\ []) do
    Metadata.put(mob_guid, %{
      tapped_player: Keyword.get(opts, :tapped_player, context.viewer),
      loot_summary: Loot.summary(loot)
    })
  end

  defp personalize(%{mob_guid: mob_guid, viewer: viewer}, character) do
    update = %UpdateObject{
      object: %Object{guid: mob_guid},
      unit: %Unit{dynamic_flags: @dynamic_flag_lootable ||| @dynamic_flag_tapped}
    }

    Tap.personalize(update, viewer, character).unit.dynamic_flags
  end

  defp quest_loot do
    %Loot{items: [%Loot.Item{slot: 0, item_id: @quest_item_id, quest_item: true}]}
  end

  defp character_on_quest do
    {:ok, quest_log} = QuestLog.add(%{}, @quest_id)
    %Character{object: %Object{guid: 1}, unit: %Unit{}, player: %Player{quest_log: quest_log}}
  end

  defp character_without_quest do
    %Character{object: %Object{guid: 1}, unit: %Unit{}, player: %Player{quest_log: %{}}}
  end
end
