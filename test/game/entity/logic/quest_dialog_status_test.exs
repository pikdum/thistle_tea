defmodule ThistleTea.Game.Entity.Logic.QuestDialogStatusTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus

  describe "for_giver/2" do
    test "returns none when the npc has no quests" do
      assert QuestDialogStatus.for_giver([], 10) == QuestDialogStatus.none()
    end

    test "returns available when the player meets the level requirement" do
      quests = [%Quest{id: 1, min_level: 5}]
      assert QuestDialogStatus.for_giver(quests, 5) == QuestDialogStatus.available()
    end

    test "returns unavailable when the player is too low level" do
      quests = [%Quest{id: 1, min_level: 5}]
      assert QuestDialogStatus.for_giver(quests, 4) == QuestDialogStatus.unavailable()
    end

    test "available wins over unavailable across multiple quests" do
      quests = [%Quest{id: 1, min_level: 20}, %Quest{id: 2, min_level: 1}]
      assert QuestDialogStatus.for_giver(quests, 5) == QuestDialogStatus.available()
    end
  end
end
