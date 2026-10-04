defmodule ThistleTea.Game.Core.AI.EventScript.ImpDeliveryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @jeevee 14_500

  describe "event_steps/1" do
    test "releasing the imp kneels the warlock and sets J'eevee loose on them" do
      assert [
               %ScriptStep{command: :emote, datalong: 16},
               %ScriptStep{
                 command: :summon_creature,
                 datalong: @jeevee,
                 datalong2: 180_000,
                 dataint3: -1,
                 dataint4: 1,
                 target_self?: true
               }
             ] = EventScript.steps_by_event()[8_438]
    end

    test "J'eevee credits the warlock after her last swing, then teleports and vanishes" do
      steps = wander()

      assert steps == Enum.sort_by(steps, & &1.delay_ms)

      assert [%ScriptStep{command: :kill_credit, datalong: @jeevee, delay_ms: credit_ms}] =
               commands(steps, :kill_credit)

      assert [%ScriptStep{datalong: 7_791, delay_ms: teleport_ms}] = commands(steps, :cast_spell)
      assert %ScriptStep{command: :despawn, delay_ms: despawn_ms} = List.last(steps)

      swings = commands(steps, :emote)
      assert length(swings) == 12
      assert Enum.all?(swings, &(&1.delay_ms < credit_ms))
      assert credit_ms <= teleport_ms and despawn_ms - teleport_ms == 2_000
      assert despawn_ms in 30_000..40_000
    end

    test "she says her four lines in order and runs only the dash between the benches" do
      steps = wander()

      assert [9_769, 9_770, 9_771, 9_742] = steps |> commands(:talk) |> Enum.map(& &1.dataint)
      moves = commands(steps, :move_to)
      assert length(moves) == 13

      assert [:walk, :walk, :walk, :walk, :walk, :walk, :walk, :walk, :run, :run, :run, :walk, :walk] =
               Enum.map(moves, &pace/1)
    end
  end

  defp wander do
    [_kneel, summon] = EventScript.steps_by_event()[8_438]
    summon.sub_scripts[summon.dataint2]
  end

  defp pace(%ScriptStep{datalong3: flags}) when Bitwise.band(flags, 0x4) != 0, do: :run
  defp pace(%ScriptStep{datalong3: flags}) when Bitwise.band(flags, 0x2) != 0, do: :walk

  defp commands(steps, command), do: Enum.filter(steps, &(&1.command == command))
end
