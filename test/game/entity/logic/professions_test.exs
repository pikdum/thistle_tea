defmodule ThistleTea.Game.Entity.Logic.ProfessionsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Professions
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Logic.Skills

  describe "plan/4" do
    test "removes active and rewarded profession quests, preserves unrelated progress and frees a slot" do
      source = Item.build(%ItemTemplate{entry: 10, start_quest: 1, stackable: 20}, 1, stack_count: 3)

      quests = [
        %Quest{id: 1, required_skill: 186, src_item_id: 10, src_item_count: 2},
        %Quest{id: 2, required_skill: 186, src_item_id: 10},
        %Quest{id: 3, required_skill: 182, src_item_id: 10},
        %Quest{id: 4, required_skill: 186, src_item_id: 10}
      ]

      player = %Player{
        bank1: 1,
        skills: skills(),
        rewarded_quests: MapSet.new([4, 5]),
        quest_log: %{0 => %Entry{quest_id: 1, expires_at_ms: 1000}, 1 => %Entry{quest_id: 2}, 2 => %Entry{quest_id: 3}}
      }

      assert {:ok, changes} = Professions.plan(player, 186, quests, lookup([source]))
      assert ChangeSet.destroyed_items(changes) == [source]
      assert changes.placements == []
      refute Skills.known?(changes.player.skills, 186)
      assert changes.player.skills[182] == player.skills[182]
      assert Skills.free_profession_slots(changes.player.skills) == 1
      assert Enum.map(QuestLog.active_entries(changes.player.quest_log), & &1.quest_id) == [3]
      assert QuestLog.timed_entries(changes.player.quest_log) == []
      assert changes.player.rewarded_quests == MapSet.new([5])
    end

    test "does not consume missing source counts or items from rewarded quests" do
      item = Item.build(%ItemTemplate{entry: 10, stackable: 20}, 1)

      player = %Player{
        inv1: 1,
        skills: skills(),
        rewarded_quests: MapSet.new([2]),
        quest_log: %{0 => %Entry{quest_id: 1}}
      }

      quests = [
        %Quest{id: 1, required_skill: 186, src_item_id: 10, src_item_count: 2},
        %Quest{id: 2, required_skill: 186, src_item_id: 10}
      ]

      assert {:ok, changes} = Professions.plan(player, 186, quests, lookup([item]))
      assert changes.destroyed == %{}
      assert changes.changed == %{}
      assert changes.player.rewarded_quests == MapSet.new()
    end

    test "rejects nonempty source bags before changing any profession progress" do
      bag = Item.build(%ItemTemplate{entry: 10, class: 1, inventory_type: 18, container_slots: 4}, 1)
      bag = %{bag | container: %{bag.container | slot_1: 2}}
      item = Item.build(%ItemTemplate{entry: 20}, 2)
      player = %Player{bag1: 1, skills: skills(), quest_log: %{0 => %Entry{quest_id: 1}}}
      quest = %Quest{id: 1, required_skill: 186, src_item_id: 10}
      assert {:error, :can_only_do_with_empty_bags} = Professions.plan(player, 186, [quest], lookup([bag, item]))
      assert Skills.free_profession_slots(player.skills) == 0
      assert QuestLog.active?(player.quest_log, 1)
    end

    test "rejects an unknown skill" do
      assert {:error, :unknown_skill} = Professions.plan(%Player{}, 186, [], lookup([]))
    end
  end

  defp skills, do: %{} |> Skills.learn_rank(186, 300) |> Skills.learn_rank(182, 75)

  defp lookup(items) do
    items = Map.new(items, &{&1.object.guid, &1})
    &Map.get(items, &1)
  end
end
