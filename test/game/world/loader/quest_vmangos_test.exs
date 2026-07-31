defmodule ThistleTea.Game.World.Loader.QuestVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  @moduletag :vmangos_db

  setup do
    QuestLoader.init()
    QuestLoader.load_all()
    :ok
  end

  describe "load_all/0" do
    test "preloads quest start scripts" do
      assert %Quest{
               start_script_id: 54,
               start_script_steps: [
                 %ScriptStep{command: :cast_spell, datalong: 6245},
                 %ScriptStep{command: :emote, datalong: 113},
                 %ScriptStep{command: :talk}
               ]
             } = QuestLoader.get(54)
    end

    test "preloads quest complete scripts" do
      assert %Quest{
               complete_script_id: 67,
               complete_script_steps: [
                 %ScriptStep{command: :summon_creature, datalong: 2044},
                 %ScriptStep{command: :attack_start}
               ]
             } = QuestLoader.get(67)
    end

    test "resolves escort event conditions and outcome scripts" do
      assert %Quest{start_script_steps: steps} = QuestLoader.get(648)
      event = Enum.find(steps, &(&1.command == :start_map_event))

      assert event.failure_condition.type == :escort
      assert event.failure_condition.value2 == 80
      assert [%ScriptStep{command: :fail_quest, datalong: 648} | _steps] = event.sub_scripts[64_801]
      assert [%ScriptStep{} | _steps] = event.sub_scripts[64_802]
    end

    test "resolves game object database guid targets" do
      assert %Quest{complete_script_steps: steps} = QuestLoader.get(848)
      step = Enum.find(steps, &(&1.command == :activate_object))

      assert step.target_type == :game_object_with_guid
      assert Guid.entity_type(step.buddy_guid) == :game_object
      assert Guid.low_guid(step.buddy_guid) == 13_292
    end
  end
end
