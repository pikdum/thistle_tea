defmodule ThistleTea.Game.Core.AI.CreatureScript.TapokeSlimJahnTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Quest.QuestEscort
  alias ThistleTea.Game.Core.Quest.QuestEscort.Catalog

  @slim 4_962
  @friend 4_971
  @missing_diplomat 1_249

  describe "events/1" do
    test "Slim gives up at a fifth of his health only while fleeing the player" do
      [give_up, _aggro, _spawned, _death] = CreatureScript.events(@slim)

      assert %{event_type: :hp, param1: 20} = give_up
      assert give_up.condition == %Condition{type: :map_event_active, value1: @missing_diplomat}

      steps = give_up.actions |> List.flatten() |> nested()

      assert %ScriptStep{command: :set_faction, datalong: 35} = Enum.find(steps, &(&1.command == :set_faction))

      assert %ScriptStep{command: :quest_explored, datalong: @missing_diplomat, target_type: :map_event_target} =
               Enum.find(steps, &(&1.command == :quest_explored))

      assert Enum.any?(steps, &match?(%ScriptStep{command: :despawn, datalong: 1_000, datalong2: 2}, &1))
    end

    test "Slim calls a friend once and boasts only on the run" do
      [_give_up, aggro, _spawned, _death] = CreatureScript.events(@slim)

      assert %Condition{type: :nearby_creature, value1: @friend, reverse?: true} = aggro.condition
      assert [cast, boast] = List.flatten(aggro.actions)
      assert %ScriptStep{command: :cast_spell, datalong: 16_457, target_self?: true} = cast
      assert %ScriptStep{command: :talk, dataint: 5_827, condition: %Condition{type: :map_event_active}} = boast
    end

    test "his friend poisons its blade and fights with backstabs and slowing poison" do
      assert [spawned, poison, backstab] = CreatureScript.events(@friend)
      assert [[%ScriptStep{command: :cast_spell, datalong: 3_616}]] = spawned.actions

      assert [[%ScriptStep{command: :cast_spell, datalong: 7_992, datalong2: 0x20, target_type: :victim}]] =
               poison.actions

      assert [[%ScriptStep{command: :cast_spell, datalong: 15_582, target_type: :victim}]] = backstab.actions
    end
  end

  describe "Catalog" do
    test "Mikhail sends Slim out of the inn, and reaching the gate fails the quest" do
      escort = Catalog.get(@missing_diplomat)

      assert %QuestEscort{entry: @slim, giver: 4_963, credit_point: nil} = escort
      assert [%ScriptStep{command: :start_script_for_all, datalong3: @slim}] = QuestEscort.start_steps(escort)

      assert escort
             |> QuestEscort.point_steps(9, 0)
             |> Map.fetch!(9)
             |> Enum.any?(&(&1.command == :fail_quest))
    end
  end

  defp nested(steps), do: Enum.flat_map(steps, &[&1 | nested(Enum.flat_map(Map.values(&1.sub_scripts), fn s -> s end))])
end
