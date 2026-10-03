defmodule ThistleTea.Game.Core.AI.CreatureScript.DaphneStilwellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Quest.QuestEscort
  alias ThistleTea.Game.Core.Quest.QuestEscort.Catalog

  @daphne 6_182
  @defias_raider 6_180
  @tome_of_valor 1_651

  describe "events/1" do
    test "Daphne cheers each beaten wave once, by the phase her escort marked it with" do
      events = CreatureScript.events(@daphne)

      assert Enum.map(events, &{&1.event_type, &1.inverse_phase_mask}) ==
               Enum.map(1..3, &{:evade, CreatureScript.only_in_phases([&1])})

      assert Enum.map(events, &List.flatten(&1.actions)) == [
               [%ScriptStep{command: :talk, dataint: 5_269}, %ScriptStep{command: :set_phase, datalong: 0}],
               [%ScriptStep{command: :talk, dataint: 2_369}, %ScriptStep{command: :set_phase, datalong: 0}],
               [%ScriptStep{command: :talk, dataint: 2_358}, %ScriptStep{command: :set_phase, datalong: 0}]
             ]
    end
  end

  describe "Catalog" do
    test "three growing Defias waves come for Daphne at her house before the walk back" do
      escort = Catalog.get(@tome_of_valor)
      assert %QuestEscort{entry: @daphne, credit_point: 17, instant_respawn?: true} = escort

      for {point, wave, raiders} <- [{7, 1, 3}, {8, 2, 4}, {9, 3, 5}] do
        steps = escort |> QuestEscort.point_steps(point, 0) |> Map.fetch!(point)
        summons = Enum.filter(steps, &(&1.command == :summon_creature))

        assert %ScriptStep{datalong: ^wave} = Enum.find(steps, &(&1.command == :set_phase))
        assert length(summons) == raiders
        assert Enum.all?(summons, &match?(%ScriptStep{datalong: @defias_raider, dataint3: 8, dataint4: 4}, &1))
      end
    end
  end
end
