defmodule ThistleTea.Game.Core.AI.CreatureScript.TwiggyFlatheadTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.TwiggyFlathead
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
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @twiggy 6248
  @big_will 6238
  @challenger 6240

  setup do
    %{twiggy: twiggy(), player: Guid.from_low_guid(:player, Unique.integer())}
  end

  describe "events/1" do
    test "a warrior in the ring starts the Affray", %{twiggy: twiggy, player: player} do
      {twiggy, blackboard} = begin(twiggy, Blackboard.new(), player)

      assert blackboard.event_ai.phase == 1
      assert [%Effects.ScriptSteps{steps: timeline, target_guid: ^player}] = events(twiggy)

      summons = Enum.filter(timeline, &(&1.command == :summon_creature))
      frays = Enum.filter(timeline, &(&1.command == :talk))

      assert Enum.map(summons, & &1.datalong) == List.duplicate(@challenger, 6) ++ [@big_will]
      assert Enum.map(summons, & &1.delay_ms) == [0, 0, 0, 0, 0, 0, 155_000]
      assert Enum.map(frays, & &1.delay_ms) == [5_000, 30_000, 55_000, 80_000, 105_000, 130_000]
    end

    test "each challenger waits its turn before turning on the player" do
      challengers = Enum.filter(timeline(), &match?(%ScriptStep{datalong: @challenger}, &1))

      releases =
        Enum.map(challengers, fn summon ->
          summon.sub_scripts
          |> Map.fetch!(summon.dataint2)
          |> Enum.find(&match?(%ScriptStep{command: :set_faction, datalong: 16}, &1))
          |> Map.fetch!(:delay_ms)
        end)

      assert releases == [5_000, 30_000, 55_000, 80_000, 105_000, 130_000]
    end

    test "Big Will walks into the ring and squares up after fifteen seconds" do
      big_will = Enum.find(timeline(), &match?(%ScriptStep{datalong: @big_will}, &1))

      assert [
               %ScriptStep{command: :set_faction, datalong: 35, delay_ms: 0},
               %ScriptStep{command: :move_to, position: {-1682.31, -4329.68, 2.78, +0.0}},
               %ScriptStep{command: :set_faction, datalong: 7, delay_ms: 15_000},
               %ScriptStep{command: :talk, dataint: 2421, delay_ms: 15_000}
             ] = Map.fetch!(big_will.sub_scripts, big_will.dataint2)
    end

    test "only one Affray runs at a time", %{twiggy: twiggy, player: player} do
      {twiggy, blackboard} = begin(twiggy, Blackboard.new(), player)
      twiggy = %{twiggy | internal: %{twiggy.internal | events: []}}

      {twiggy, _blackboard} = begin(twiggy, blackboard, player)

      assert events(twiggy) == []
    end

    test "the Affray is over when Big Will falls", %{twiggy: twiggy, player: player} do
      [_begin, down, over, _gone, _crowd] = CreatureScript.events(@twiggy)

      assert %{event_type: :summoned_just_died, param1: @challenger, actions: [[%ScriptStep{dataint: 2355}]]} = down

      assert %{
               event_type: :summoned_just_died,
               param1: @big_will,
               actions: [[%ScriptStep{dataint: 2320}, %ScriptStep{command: :set_phase, datalong: 0}]]
             } = over

      {_twiggy, blackboard} = begin(twiggy, Blackboard.new(), player)
      assert blackboard.event_ai.phase == 1
    end
  end

  defp begin(twiggy, blackboard, player) do
    EventAI.on_script_event(twiggy, blackboard, TwiggyFlathead.begin_event(), 0, player, 0, Context.new(0))
  end

  defp timeline do
    [begin | _events] = CreatureScript.events(@twiggy)
    fight = begin.actions |> List.flatten() |> Enum.find(&(&1.command == :start_script))
    Map.fetch!(fight.sub_scripts, fight.datalong)
  end

  defp events(twiggy), do: Enum.filter(twiggy.internal.events, &match?(%Effects.ScriptSteps{}, &1))

  defp twiggy do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @twiggy, Unique.integer()), entry: @twiggy},
      unit: %Unit{health: 1_000, max_health: 1_000, level: 35, auras: [], flags: 0, faction_template: 35},
      movement_block: %MovementBlock{position: {-1686.14, -4323.04, 4.28, 5.34}},
      internal: %Internal{
        world: %WorldRef{map_id: 1},
        name: "Twiggy Flathead",
        creature: %Creature{ai_events: CreatureScript.events(@twiggy)}
      }
    }
  end
end
