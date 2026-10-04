defmodule ThistleTea.Game.Core.AI.CreatureScript.ErisHavenfireTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @eris 14_494
  @injured 14_484
  @plagued 14_485
  @footsoldier 14_486
  @archer 14_489
  @quest 7_622
  @running %Condition{type: :map_event_active, value1: @quest}

  describe "CreatureScript registry" do
    test "ports Eris and every creature her trial calls" do
      assert Enum.all?([@eris, @injured, @plagued, @footsoldier, @archer], &CreatureScript.ported?/1)
      assert Enum.all?([@injured, @plagued, @footsoldier, @archer], &(&1 in CreatureScript.summon_entries()))
    end
  end

  describe "quest_start_steps/0" do
    test "accepting the trial opens its event, lights the sanctuary, and posts eight archers" do
      [event, light | rest] = Map.fetch!(CreatureScript.quest_start_steps(), @quest)
      {archers, [timeline]} = Enum.split(rest, 8)

      assert %ScriptStep{command: :start_map_event, datalong: @quest, abort_on_failure?: true} = event
      assert %Condition{type: :map_event_data, value2: 0, value3: 50, value4: 1} = event.success_condition

      assert %Condition{
               type: :or,
               children: [
                 %Condition{type: :map_event_data, value2: 1, value3: 15, value4: 1},
                 %Condition{type: :escort}
               ]
             } = event.failure_condition

      assert [%ScriptStep{command: :quest_explored, datalong: @quest} | _] = event.sub_scripts[event.dataint2]

      assert [%ScriptStep{command: :fail_quest}, _say, _light, _phase, %ScriptStep{command: :despawn, datalong2: 300}] =
               event.sub_scripts[event.dataint4]

      assert %ScriptStep{command: :summon_object, datalong: 179_693} = light
      assert Enum.all?(archers, &match?(%ScriptStep{command: :summon_creature, datalong: @archer, dataint4: 7}, &1))
      assert %ScriptStep{command: :start_script, sub_scripts: %{1 => _steps}} = timeline
    end

    test "five waves flee every eighty seconds and the Scourge assault joins at the hundredth" do
      steps = timeline()

      assert Enum.map(steps, & &1.delay_ms) == [10_000, 90_000, 100_000, 170_000, 250_000, 330_000]
      assert Enum.all?(steps, &(&1.condition == @running))
      assert %ScriptStep{command: :set_phase, datalong: 1} = Enum.at(steps, 2)

      waves = List.delete_at(steps, 2)

      for {wave, size} <- Enum.zip(waves, [12, 12, 12, 13, 16]) do
        for {choice, plagued} <- Enum.with_index(wave_choices(wave), 1) do
          assert headcount(choice) == %{@plagued => plagued, @injured => size - plagued}
          assert [%ScriptStep{dataint2: cry, sub_scripts: cries} | _] = choice
          assert [%ScriptStep{command: :talk}] = cries[cry]
        end
      end
    end

    test "a wave summons its peasants scattered at the burning village" do
      [first_wave | _] = timeline()
      eris = mob(@eris)
      context = Context.new(0, random: Random.fixed(0.5, 30))

      {eris, _blackboard} =
        Script.run(eris, Blackboard.new(), [%{first_wave | condition: nil, delay_ms: 0}], nil, context)

      summons = Enum.filter(eris.internal.events, &match?(%Effects.SummonCreature{}, &1))
      assert length(summons) == 12
      assert Enum.all?(summons, &match?(%{summon: %{scatter: 6.0, despawn_type: 7, attack_guid: nil}}, &1))
    end
  end

  describe "events/1" do
    test "Eris blesses the field and sends footsoldiers only once the assault starts" do
      [footsoldiers, blessing] = CreatureScript.events(@eris)

      assert footsoldiers.chance == 85
      assert {footsoldiers.param3, footsoldiers.param4} == {10_000, 14_000}
      assert footsoldiers.inverse_phase_mask == CreatureScript.only_in_phases([1])
      assert blessing.inverse_phase_mask == CreatureScript.only_in_phases([1])

      assert [%ScriptStep{command: :cast_spell, datalong: 23_108}, %ScriptStep{dataint: 9_655} = say] =
               hd(blessing.actions)

      assert {say.target_type, say.target_param1} == {:map_event_target, @quest}

      summons = footsoldiers.actions |> List.flatten() |> nested() |> Enum.filter(&(&1.command == :summon_creature))
      assert Enum.all?(summons, &(&1.datalong == @footsoldier and &1.target_param1 == @quest))
      assert summons |> Enum.map(& &1.dataint3) |> Enum.uniq() |> Enum.sort() == [-1, 23]
    end

    test "a peasant stays passive, joins the trial, and walks to the road and on to the light" do
      [spawned, road, light | _rest] = CreatureScript.events(@plagued)

      assert [
               %ScriptStep{command: :set_react_state, datalong: 0},
               %ScriptStep{command: :add_map_event_target, datalong: @quest},
               %ScriptStep{command: :cast_spell, datalong: 23_072, target_self?: true},
               %ScriptStep{command: :move_to, datalong: 3, datalong3: 3, datalong4: 2, dataint: 1}
             ] = hd(spawned.actions)

      assert {road.param1, road.param2} == {9, 1}
      assert [%ScriptStep{command: :move_to, datalong: 3, dataint: 2}] = hd(road.actions)
      assert {light.param1, light.param2} == {9, 2}

      assert [
               %ScriptStep{command: :set_map_event_data, datalong2: 0, datalong4: 1},
               _farewell,
               %ScriptStep{command: :despawn}
             ] =
               hd(light.actions)

      [injured_spawned | _rest] = CreatureScript.events(@injured)
      refute Enum.any?(hd(injured_spawned.actions), &(&1.command == :cast_spell))
    end

    test "an archer's arrow hits harder than its spell and sometimes opens Death's Door" do
      [_spawned, _road, _light, _death, bonus, deaths_door | _says] = CreatureScript.events(@injured)

      assert {bonus.event_type, bonus.param1, bonus.chance} == {:hit_by_spell, 23_073, 100}
      assert [%ScriptStep{command: :deal_damage, datalong: 57, target_self?: true}] = hd(bonus.actions)
      assert {deaths_door.param1, deaths_door.chance} == {23_073, 9}
      assert [%ScriptStep{command: :cast_spell, datalong: 23_127}] = hd(deaths_door.actions)
    end

    test "the light hangs each fallen peasant on the next death post" do
      [_spawned, _road, _light, death | _rest] = CreatureScript.events(@injured)

      assert [
               %ScriptStep{
                 command: :start_script,
                 target_type: :nearest_game_object_with_entry,
                 target_param1: 179_693,
                 swap_final?: true,
                 sub_scripts: %{1 => posts}
               },
               %ScriptStep{command: :set_map_event_data, datalong2: 1, datalong4: 1}
             ] = hd(death.actions)

      assert length(posts) == 14
      assert Enum.map(posts, & &1.condition.value3) == Enum.to_list(0..13)
      assert Enum.all?(posts, &match?(%Condition{type: :map_event_data, value2: 1, value4: 0}, &1.condition))

      third = Enum.at(posts, 2).condition
      results = Map.new(posts, &{&1.condition, &1.condition == third})
      raiser = mob(@eris)
      context = Context.new(0, script_conditions: results)

      {raiser, _blackboard} = Script.run(raiser, Blackboard.new(), posts, nil, context)

      assert [%Effects.SummonGameObject{entry: 179_695, duration_ms: 1_200_000, position: position}] =
               Enum.filter(raiser.internal.events, &match?(%Effects.SummonGameObject{}, &1))

      assert {3_353.07, -3_009.16, _z, _o} = position
    end

    test "archers loose at random peasants from their posts" do
      [spawned, ooc, in_combat] = CreatureScript.events(@archer)

      assert [%ScriptStep{command: :add_map_event_target}, %ScriptStep{command: :set_sheath, datalong: 2}] =
               hd(spawned.actions)

      assert {ooc.param1, ooc.param3, ooc.param4} == {5_000, 3_000, 4_400}
      assert in_combat.event_type == :timer_in_combat

      shots = ooc.actions |> List.flatten() |> nested() |> Enum.filter(&(&1.command == :cast_spell))

      assert Enum.map(shots, &{&1.datalong, &1.target_type, &1.target_param1}) == [
               {23_073, :random_creature_with_entry, @injured},
               {23_073, :random_creature_with_entry, @plagued}
             ]
    end
  end

  defp timeline do
    [_event, _light | rest] = Map.fetch!(CreatureScript.quest_start_steps(), @quest)
    %ScriptStep{sub_scripts: %{1 => steps}} = List.last(rest)
    steps
  end

  defp wave_choices(%ScriptStep{command: :start_script, sub_scripts: choices}) do
    choices |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
  end

  defp headcount(choice) do
    Enum.reduce(choice, %{}, fn %ScriptStep{datalong: entry, count: count}, acc ->
      Map.update(acc, entry, count, &(&1 + count))
    end)
  end

  defp nested(steps) do
    Enum.flat_map(steps, fn
      %ScriptStep{command: :start_script, sub_scripts: scripts} -> scripts |> Map.values() |> List.flatten() |> nested()
      step -> [step]
    end)
  end

  defp mob(entry) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 3_000, max_health: 3_000, level: 60, auras: [], flags: 0, stand_state: 0},
      movement_block: %MovementBlock{position: {3_325.62, -2_996.32, 164.42, 6.1}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        name: "Eris Havenfire",
        creature: %Creature{ai_events: CreatureScript.events(entry)}
      }
    }
  end
end
