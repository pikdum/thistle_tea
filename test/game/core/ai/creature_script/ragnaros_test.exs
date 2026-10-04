defmodule ThistleTea.Game.Core.AI.CreatureScript.RagnarosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @ragnaros 11_502
  @majordomo 12_018
  @son_of_flame 12_143
  @lair {838.308, -831.466, -232.185}

  setup do
    player = Guid.from_low_guid(:player, Unique.integer())
    %{player: player, ragnaros: ragnaros(player)}
  end

  describe "events/1" do
    test "he rises, rebukes Majordomo, and burns him to ash" do
      %{actions: [[stay, %ScriptStep{command: :start_script, sub_scripts: %{1 => arrival}}]]} =
        event(:spawned)

      assert %ScriptStep{command: :set_combat_movement, datalong: 0} = stay
      assert [7_636, 7_662] = for(%ScriptStep{command: :talk, dataint: text} <- arrival, do: text)

      assert %ScriptStep{
               command: :cast_spell,
               datalong: 19_773,
               target_type: :nearest_creature_with_entry,
               target_param1: @majordomo
             } = List.last(arrival)
    end

    test "he submerges and eight Sons of Flame rise", %{ragnaros: ragnaros, player: player} do
      {ragnaros, blackboard} = submerge(ragnaros, Blackboard.new(), player)

      assert blackboard.event_ai.phase == 1
      assert ragnaros.unit.stand_state == 9

      %{actions: [steps]} = Enum.find(CreatureScript.events(@ragnaros), &(&1.id == @ragnaros * 100 + 8))
      sons = for %ScriptStep{command: :summon_creature, datalong: @son_of_flame} = son <- steps, do: son
      assert length(sons) == 8
      assert Enum.all?(sons, &(&1.dataint3 == 4))
    end

    test "only his first submerge calls for servants", %{ragnaros: ragnaros, player: player} do
      talks = fn phase ->
        for %{event_type: :script_event, param1: 1, inverse_phase_mask: mask, actions: [steps]} <-
              CreatureScript.events(@ragnaros),
            mask == CreatureScript.only_in_phases([phase]),
            %ScriptStep{command: :talk, dataint: text} <- steps,
            do: text
      end

      assert talks.(0) == [8_572]
      assert talks.(2) == [8_573]

      {_ragnaros, blackboard} = submerge(ragnaros, in_phase(2), player)
      assert blackboard.event_ai.phase == 1
    end

    test "he emerges once every son has fallen", %{ragnaros: ragnaros, player: player} do
      %{actions: [[emerge]], inverse_phase_mask: mask} = event(:summoned_just_died)

      assert mask == CreatureScript.only_in_phases([1])
      assert %ScriptStep{command: :send_script_event, datalong: 2, target_self?: true} = emerge
      assert %Condition{type: :nearby_creature, value1: @son_of_flame, reverse?: true} = emerge.condition

      {ragnaros, blackboard} =
        EventAI.on_script_event(ragnaros, in_phase(1), 2, 0, nil, 1_000, context(ragnaros, player))

      assert blackboard.event_ai.phase == 2
      assert ragnaros.unit.stand_state == 0
    end

    test "a son falling while he is above ground changes nothing", %{ragnaros: ragnaros, player: player} do
      son = Guid.from_low_guid(:mob, @son_of_flame, Unique.integer())

      event = %SummonEvent{
        event: :summoned_just_died,
        entry: @son_of_flame,
        world: ragnaros.internal.world,
        observation: %Observation{guid: son}
      }

      {ragnaros, blackboard} = EventAI.on_summon_event(ragnaros, Blackboard.new(), event, context(ragnaros, player))
      assert blackboard.event_ai.phase == 0
      assert ragnaros.internal.events == []
    end

    test "Magma Blast waits until no one stands within reach of his hammer" do
      %{condition: condition, param1: 3_000, param3: 2_500} =
        Enum.find(CreatureScript.events(@ragnaros), &(&1.id == @ragnaros * 100 + 7))

      assert %Condition{type: :distance_to_target, value1: 23, value2: 1} = condition
    end

    test "a wipe brings him back up, ends the cycle, and sends the sons away", %{ragnaros: ragnaros, player: player} do
      {ragnaros, blackboard} = submerge(ragnaros, Blackboard.new(), player)
      assert [emerge_later] = Map.keys(ragnaros.internal.scripts.runs)

      {ragnaros, blackboard} = EventAI.on_evade(ragnaros, blackboard, 1_000, context(ragnaros, player))

      assert blackboard.event_ai.phase == 0
      assert ragnaros.unit.stand_state == 0
      refute Map.has_key?(ragnaros.internal.scripts.runs, emerge_later)

      %{actions: [steps]} = event(:evade)
      assert %ScriptStep{command: :start_script_for_all, datalong3: @son_of_flame} = List.last(steps)
    end

    test "he does not gloat over Majordomo" do
      assert %{param3: 1, actions: [[%ScriptStep{command: :talk, dataint: 7_626}]]} = event(:kill)
    end
  end

  defp event(type), do: Enum.find(CreatureScript.events(@ragnaros), &(&1.event_type == type))

  defp submerge(ragnaros, blackboard, player),
    do: EventAI.on_script_event(ragnaros, blackboard, 1, 0, nil, 1_000, context(ragnaros, player))

  defp in_phase(phase) do
    blackboard = Blackboard.new()
    %{blackboard | event_ai: %{blackboard.event_ai | phase: phase}}
  end

  defp context(%Mob{object: %Object{guid: guid}}, player) do
    {x, y, z} = @lair

    observations = %{
      player => %Observation{guid: player, position: {WorldRef.open(409), x + 5.0, y, z}, metadata: %{alive?: true}},
      guid => %Observation{guid: guid, metadata: %{}}
    }

    Context.new(1_000, perception: Perception.new(1_000, nil, observations, %{}))
  end

  defp ragnaros(player) do
    {x, y, z} = @lair

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @ragnaros, Unique.integer()), entry: @ragnaros},
      unit: %Unit{health: 100, max_health: 100, level: 63, auras: [], flags: 0, target: player},
      movement_block: %MovementBlock{position: {x, y, z, 2.19911}},
      internal: %Internal{
        world: WorldRef.open(409),
        in_combat: true,
        threat: %{player => 100},
        creature: %Creature{ai_events: CreatureScript.events(@ragnaros)},
        spellbook: %{}
      }
    }
  end
end
