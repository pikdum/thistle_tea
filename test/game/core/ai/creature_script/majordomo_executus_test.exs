defmodule ThistleTea.Game.Core.AI.CreatureScript.MajordomoExecutusTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
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

  @majordomo 12_018
  @healer 11_663
  @elite 11_664
  @ragnaros 11_502
  @immune_to_player 0x100

  setup do
    player = Guid.from_low_guid(:player, Unique.integer())
    %{player: player, majordomo: majordomo(player)}
  end

  describe "events/1" do
    test "he arrives with four elites and four healers bound to him" do
      %{actions: [[talk | guard]]} = Enum.find(CreatureScript.events(@majordomo), &(&1.event_type == :spawned))

      assert %ScriptStep{command: :talk, dataint: 7_566} = talk
      assert guard |> Enum.map(& &1.datalong) |> Enum.frequencies() == %{@elite => 4, @healer => 4}

      for %ScriptStep{command: :summon_creature, dataint3: -1, sub_scripts: %{1 => [join]}} <- guard do
        assert %ScriptStep{command: :join_creature_group, target_param1: @majordomo} = join
      end
    end

    test "each fallen guard moves the count on by one", %{majordomo: majordomo, player: player} do
      context = context(majordomo, player)

      {majordomo, blackboard} =
        Enum.reduce([@elite, @healer, @elite], {majordomo, Blackboard.new()}, fn entry, {majordomo, blackboard} ->
          guard_dies(majordomo, blackboard, entry, context)
        end)

      assert blackboard.event_ai.phase == 3
      assert majordomo.unit.flags == 0
    end

    test "the last guard to fall ends the fight and settles his encounter", %{majordomo: majordomo, player: player} do
      {majordomo, blackboard} = guard_dies(majordomo, in_phase(7), @healer, context(majordomo, player))

      assert blackboard.event_ai.phase == 8
      assert (majordomo.unit.flags &&& @immune_to_player) != 0
      assert Enum.any?(majordomo.internal.events, &match?(%Effects.InstanceDataCommand{field: 8, value: 3}, &1))
      assert Enum.any?(majordomo.internal.events, &match?(%Effects.EnterEvade{}, &1))
    end

    test "a wipe sends the guard away and calls a fresh one", %{majordomo: majordomo, player: player} do
      {_majordomo, blackboard} = EventAI.on_evade(majordomo, in_phase(5), 1_000, context(majordomo, player))
      assert blackboard.event_ai.phase == 0

      %{actions: [steps]} =
        Enum.find(CreatureScript.events(@majordomo), &(&1.id == @majordomo * 100 + 2))

      assert [%ScriptStep{command: :set_phase, datalong: 0} | rest] = steps
      assert Enum.count(rest, &(&1.command == :start_script_for_all)) == 2
      assert Enum.count(rest, &(&1.command == :summon_creature)) == 8
    end

    test "defeated, he gives his speech and waits in the lair", %{majordomo: majordomo, player: player} do
      {majordomo, blackboard} = EventAI.on_evade(majordomo, in_phase(8), 1_000, context(majordomo, player))

      assert blackboard.event_ai.phase == 8
      assert map_size(majordomo.internal.scripts.runs) == 1
    end

    test "his gossip in the lair starts the summoning only once", %{majordomo: majordomo, player: player} do
      context = context(majordomo, player)
      {summoning, blackboard} = EventAI.on_script_event(majordomo, in_phase(9), 0, 0, player, 1_000, context)

      assert blackboard.event_ai.phase == 10
      assert map_size(summoning.internal.scripts.runs) == 1

      {_again, blackboard} = EventAI.on_script_event(summoning, blackboard, 0, 0, player, 1_000, context)
      assert blackboard.event_ai.phase == 10
    end

    test "the summoning calls up Ragnaros and lowers his own immortality" do
      %{actions: [[_phase, _gossip, %ScriptStep{command: :start_script, sub_scripts: %{1 => steps}}]]} =
        Enum.find(CreatureScript.events(@majordomo), &(&1.event_type == :script_event))

      assert Enum.any?(steps, &match?(%ScriptStep{command: :summon_creature, datalong: @ragnaros}, &1))
      assert %ScriptStep{command: :invincibility, datalong: 0} = List.last(steps)
    end
  end

  defp guard_dies(majordomo, blackboard, entry, context) do
    guard = Guid.from_low_guid(:mob, entry, Unique.integer())

    event = %SummonEvent{
      event: :summoned_just_died,
      entry: entry,
      world: majordomo.internal.world,
      observation: %Observation{guid: guard}
    }

    EventAI.on_summon_event(majordomo, blackboard, event, context)
  end

  defp in_phase(phase) do
    blackboard = Blackboard.new()
    %{blackboard | event_ai: %{blackboard.event_ai | phase: phase}}
  end

  defp context(%Mob{object: %Object{guid: guid}}, player) do
    observations = %{
      player => %Observation{
        guid: player,
        position: {WorldRef.open(409), 750.0, -1_176.0, -119.0},
        metadata: %{alive?: true}
      },
      guid => %Observation{guid: guid, metadata: %{}}
    }

    Context.new(1_000, perception: Perception.new(1_000, nil, observations, %{}))
  end

  defp majordomo(player) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @majordomo, Unique.integer()), entry: @majordomo},
      unit: %Unit{health: 100, max_health: 100, level: 63, auras: [], flags: 0, target: player},
      movement_block: %MovementBlock{position: {758.089, -1_176.71, -118.640, 3.12414}},
      internal: %Internal{
        world: WorldRef.open(409),
        in_combat: true,
        threat: %{player => 100},
        creature: %Creature{ai_events: CreatureScript.events(@majordomo)},
        spellbook: %{}
      }
    }
  end
end
