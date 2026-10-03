defmodule ThistleTea.Game.Core.AI.CreatureScript.CapturedFelwoodOoze do
  @moduledoc """
  vmangos `mob_captured_felwood_ooze`, Melding of Influences (4642) in
  Un'Goro Crater.

  Releasing the Encased Corrupt Ooze near a Primal Ooze frees a Captured
  Felwood Ooze, which creeps after the nearest Primal Ooze within thirty
  yards and melds with it once close: its Merging Oozes cast raises a
  Gargantuan Ooze, whose remains hold the quest's sample. A captured ooze
  with no Primal Ooze in reach dissolves. It looks again every two seconds,
  as the C++ script reissues its follow.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @captured_ooze 10_290
  @primal_ooze 6_557
  @merging_oozes 16_032

  @search_yards 30
  @merge_yards 5
  @follow_distance 2.0
  @follow 15
  @first_look_ms 1_000
  @look_again_ms 2_000

  @impl CreatureScript
  def entries, do: [@captured_ooze]

  @impl CreatureScript
  def events(@captured_ooze = entry) do
    [
      look(entry, 1, near(@merge_yards), [merge()]),
      look(entry, 2, %Condition{type: :and, children: [near(@search_yards), far(@merge_yards)]}, [follow()]),
      look(entry, 3, far(@search_yards), [%ScriptStep{command: :despawn}])
    ]
  end

  defp look(entry, index, condition, actions) do
    CreatureScript.event(entry, index, :timer_ooc, actions,
      condition: condition,
      param1: @first_look_ms,
      param2: @first_look_ms,
      param3: @look_again_ms,
      param4: @look_again_ms
    )
  end

  defp merge, do: primal_ooze(%ScriptStep{command: :cast_spell, datalong: @merging_oozes}, @merge_yards)

  defp follow do
    primal_ooze(
      %ScriptStep{command: :movement, datalong: @follow, position: {@follow_distance, 0.0, 0.0, 0.0}},
      @search_yards
    )
  end

  defp primal_ooze(%ScriptStep{} = step, yards),
    do: %{step | target_type: :nearest_creature_with_entry, target_param1: @primal_ooze, target_param2: yards}

  defp near(yards), do: %Condition{type: :nearby_creature, value1: @primal_ooze, value2: yards, swap_targets?: true}

  defp far(yards), do: %{near(yards) | reverse?: true}
end
