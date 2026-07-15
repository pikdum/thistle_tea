defmodule ThistleTea.Game.Entity.Data.QuestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Quest

  describe "build/1" do
    test "translates core fields from a quest_template row" do
      row = %Mangos.QuestTemplate{
        entry: 33,
        method: 2,
        min_level: 3,
        quest_level: 8,
        required_races: 1,
        required_classes: 0,
        prev_quest_id: 0,
        src_item_id: 0,
        title: "Wolves Across the Border",
        details: "Kill some wolves.",
        objectives: "Bring 8 pelts."
      }

      quest = Quest.build(row)

      assert quest.id == 33
      assert quest.min_level == 3
      assert quest.level == 8
      assert quest.required_races == 1
      assert quest.title == "Wolves Across the Border"
      assert quest.objective_texts == ["", "", "", ""]
    end

    test "translates delayed mail rewards" do
      row = %Mangos.QuestTemplate{
        entry: 1141,
        rew_mail_template_id: 87,
        rew_mail_delay_secs: 86_400,
        rew_mail_money: 50
      }

      quest = Quest.build(row)

      assert quest.reward_mail_template_id == 87
      assert quest.reward_mail_delay_secs == 86_400
      assert quest.reward_mail_money == 50
    end

    test "normalizes kill objectives with slot indexes, skipping empty and gameobject slots" do
      row = %Mangos.QuestTemplate{
        entry: 1,
        req_creature_or_go_id1: 299,
        req_creature_or_go_count1: 8,
        req_creature_or_go_id2: -55,
        req_creature_or_go_count2: 3,
        req_creature_or_go_id3: 300,
        req_creature_or_go_count3: 0
      }

      assert Quest.build(row).required_kills == [{0, 299, 8}, {2, 300, 1}]
    end

    test "skips kill slots that are spell-cast objectives" do
      row = %Mangos.QuestTemplate{
        entry: 1,
        req_creature_or_go_id1: 299,
        req_creature_or_go_count1: 8,
        req_spell_cast1: 12_345
      }

      assert Quest.build(row).required_kills == []
    end

    test "normalizes item objectives and rewards" do
      row = %Mangos.QuestTemplate{
        entry: 2,
        req_item_id2: 750,
        req_item_count2: 4,
        rew_item_id1: 80,
        rew_item_count1: 1,
        rew_choice_item_id1: 90,
        rew_choice_item_count1: 2,
        rew_choice_item_id2: 91,
        rew_choice_item_count2: 1,
        rew_or_req_money: 150
      }

      quest = Quest.build(row)

      assert quest.required_items == [{1, 750, 4}]
      assert quest.reward_items == [{80, 1}]
      assert quest.reward_choice_items == [{90, 2}, {91, 1}]
      assert quest.reward_money == 150
      assert Quest.deliver?(quest)
    end

    test "nil text columns become empty strings" do
      row = %Mangos.QuestTemplate{entry: 3, title: nil, details: nil, objectives: nil}
      quest = Quest.build(row)

      assert quest.title == ""
      assert quest.details == ""
      assert quest.objectives_text == ""
    end
  end

  describe "auto_complete?/1" do
    test "true only for method 0" do
      assert Quest.auto_complete?(%Quest{method: 0})
      refute Quest.auto_complete?(%Quest{method: 2})
    end
  end
end
