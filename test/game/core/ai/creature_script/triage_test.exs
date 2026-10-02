defmodule ThistleTea.Game.Core.AI.CreatureScript.TriageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
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

  @alliance_doctor 12_939
  @alliance_quest 6_624
  @critically_injured 12_937
  @injured 12_938
  @triage 20_804
  @first_bunk {-3757.38, -4533.05, 14.16}
  @second_bunk {-3754.36, -4539.13, 14.16, 5.13}

  describe "CreatureScript registry" do
    test "ports both doctors and all six patients" do
      for entry <- [12_920, 12_939, 12_923, 12_924, 12_925, 12_936, 12_937, 12_938] do
        assert CreatureScript.ported?(entry)
      end
    end

    test "appends a start script to both Triage quests and preloads every patient" do
      assert %{6_622 => [_ | _], 6_624 => [_ | _]} = CreatureScript.quest_start_steps()
      assert Enum.all?([12_923, 12_924, 12_925, 12_936, 12_937, 12_938], &(&1 in CreatureScript.summon_entries()))
    end
  end

  describe "quest_start_steps/0" do
    test "accepting opens the quest's map event before waking the doctor" do
      [start_event, wake] = Map.fetch!(CreatureScript.quest_start_steps(), @alliance_quest)

      assert %ScriptStep{command: :start_map_event, datalong: @alliance_quest, abort_on_failure?: true} = start_event
      assert %ScriptStep{command: :set_phase, datalong: 1} = wake
      assert [%ScriptStep{command: :quest_explored}, _sleep] = start_event.sub_scripts[start_event.dataint2]
      assert [%ScriptStep{command: :fail_quest}, _sleep] = start_event.sub_scripts[start_event.dataint4]
    end
  end

  describe "doctor" do
    test "lays a patient in the first free bunk" do
      doctor = mob(@alliance_doctor, health: 3_000)
      [summon_timer] = CreatureScript.events(@alliance_doctor)
      context = Context.new(0, perception: bunk_perception([occupant(@first_bunk)]))

      {doctor, _blackboard} = Script.run(doctor, Blackboard.new(), List.flatten(summon_timer.actions), nil, context)

      assert [%Effects.SummonCreature{summon: %{entry: @injured, position: @second_bunk}}] = doctor.internal.events
    end

    test "summons nobody while every bunk is taken" do
      doctor = mob(@alliance_doctor, health: 3_000)
      [summon_timer] = CreatureScript.events(@alliance_doctor)

      bunks = List.first(summon_timer.actions) |> hd() |> Map.fetch!(:sub_scripts) |> Map.fetch!(@injured)
      [%ScriptStep{positions: positions}] = bunks
      occupants = Enum.map(positions, fn {x, y, z, _o} -> occupant({x, y, z}) end)
      context = Context.new(0, perception: bunk_perception(occupants))

      {doctor, _blackboard} = Script.run(doctor, Blackboard.new(), List.flatten(summon_timer.actions), nil, context)

      assert doctor.internal.events == []
    end
  end

  describe "patient" do
    test "arrives lying down at its injury's health without regenerating" do
      patient = mob(@critically_injured, health: 4_000)

      {patient, _blackboard} = EventAI.on_spawned(patient, Blackboard.new(), 0, Context.new(0))

      assert patient.unit.health == 1_000
      assert patient.unit.stand_state == 7
      assert patient.internal.creature.regenerate_stats == 0

      assert [%Effects.ScriptedEventCommand{step: %ScriptStep{command: :add_map_event_target} = step}] =
               Enum.filter(patient.internal.events, &match?(%Effects.ScriptedEventCommand{}, &1))

      assert step.datalong == @alliance_quest
    end

    test "bleeds out and counts its death" do
      patient = mob(@critically_injured, health: 4_000)
      patient = %{patient | unit: %{patient.unit | health: 40}}
      [_spawned, bleed, _death, _saved] = CreatureScript.events(@critically_injured)

      {patient, _blackboard} = Script.run(patient, Blackboard.new(), List.flatten(bleed.actions), nil, Context.new(0))

      assert patient.unit.health == 0
    end

    test "is saved once by a Triage Bandage" do
      player = Guid.from_low_guid(:player, Unique.integer())
      patient = mob(@critically_injured, health: 4_000)

      {patient, blackboard} = EventAI.on_spell_hit(patient, Blackboard.new(), player, @triage, 0, Context.new(0))

      assert patient.unit.stand_state == 0
      assert patient.internal.creature.regenerate_stats == 3
      assert Bitwise.band(patient.unit.flags, 0x02000000) != 0
      [_spawned, _bleed, _death, saved] = CreatureScript.events(@critically_injured)
      assert [8_355, 8_359, 8_361] in Enum.map(List.flatten(saved.actions), &ScriptStep.talk_text_ids/1)
      assert Enum.any?(patient.internal.events, &match?(%Effects.DespawnSelf{duration_ms: 5_000}, &1))

      patient = %{patient | internal: %{patient.internal | events: []}}
      {patient, _blackboard} = EventAI.on_spell_hit(patient, blackboard, player, @triage, 0, Context.new(0))

      assert patient.internal.events == []
    end
  end

  defp bunk_perception(occupants) do
    observations = Map.new(occupants, fn {guid, observation} -> {guid, observation} end)
    nearby = %{mobs: Enum.map(occupants, fn {guid, _observation} -> {guid, 5.0} end), players: [], game_objects: []}
    Perception.new(0, nil, observations, nearby)
  end

  defp occupant({x, y, z}) do
    guid = Guid.from_low_guid(:mob, @injured, Unique.integer())

    {guid, %Observation{guid: guid, distance: 5.0, position: {WorldRef.coerce(1), x, y, z}, metadata: %{alive?: true}}}
  end

  defp mob(entry, opts) do
    max_health = Keyword.fetch!(opts, :health)

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: max_health, max_health: max_health, level: 45, auras: [], flags: 0, stand_state: 0},
      movement_block: %MovementBlock{position: {-3747.27, -4532.25, 11.99, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 1},
        name: "Triage",
        creature: %Creature{ai_events: CreatureScript.events(entry), regenerate_stats: 3}
      }
    }
  end
end
