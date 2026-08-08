defmodule ThistleTea.Game.World.Loader.QuestVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.ItemTemplate
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
    test "preloads every required condition tree" do
      conditioned_quests =
        QuestLoader
        |> :ets.tab2list()
        |> Enum.flat_map(fn
          {{:quest, _quest_id}, %Quest{required_condition_id: condition_id} = quest} when condition_id > 0 -> [quest]
          _entry -> []
        end)

      assert length(conditioned_quests) == 76

      Enum.each(conditioned_quests, fn quest ->
        assert %Condition{entry: entry} = quest.required_condition
        assert entry == quest.required_condition_id

        refute Enum.any?(flatten(quest.required_condition), fn condition ->
                 condition.type == {:unsupported, :unresolved}
               end)
      end)
    end

    test "resolves pinned bank, quest availability, and instance data roots" do
      assert %Quest{required_condition: taste_of_flame} = QuestLoader.get(4_022)
      assert Enum.any?(flatten(taste_of_flame), &(&1.type == :item_with_bank and &1.value1 == 10_575))

      assert %Quest{required_condition: zameks_distraction} = QuestLoader.get(1_191)
      assert Enum.any?(flatten(zameks_distraction), &(&1.type == :quest_available and &1.value1 == 1_194))
      assert %Quest{required_condition_id: 0, required_condition: nil} = QuestLoader.get(1_194)

      assert %Quest{required_condition: %Condition{entry: 3_755, type: :instance_data}} = QuestLoader.get(5_122)
      assert %Quest{required_condition: %Condition{entry: 3_757, type: :instance_data}} = QuestLoader.get(5_125)
    end

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

    test "preloads scripted game object spawns" do
      assert %Quest{complete_script_steps: steps} = QuestLoader.get(308)
      step = Enum.find(steps, &(&1.command == :respawn_game_object))

      assert step.datalong == 35_875
      assert step.game_object_spawn.object.entry == 270
      assert Guid.low_guid(step.game_object_spawn.object.guid) == 35_875
    end

    test "resolves script termination conditions" do
      assert %Quest{start_script_steps: steps} = QuestLoader.get(5_713)
      step = Enum.find(steps, &(&1.command == :terminate_condition))

      assert step.termination_condition.entry == 5_713
      assert step.termination_condition.type == :map_event_active
    end

    test "preloads scripted equipment item templates" do
      assert %Quest{complete_script_steps: steps} = QuestLoader.get(112)
      step = Enum.find(steps, &(&1.command == :set_equipment and &1.delay_ms == 0))

      assert [
               %ItemTemplate{entry: 3_699},
               %ItemTemplate{entry: 3_697},
               :unchanged
             ] = step.equipment_items
    end

    test "preloads scripted door spawns" do
      assert %Quest{start_script_steps: steps} = QuestLoader.get(6_482)
      step = Enum.find(steps, &(&1.command == :open_door))

      assert step.datalong == 48_166
      assert Guid.low_guid(step.game_object_spawn.object.guid) == 48_166
    end
  end

  defp flatten(%Condition{children: children} = condition) do
    [condition | Enum.flat_map(children, &flatten/1)]
  end
end
