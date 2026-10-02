defmodule ThistleTea.Game.Core.AI.CreatureScript.RabidThistleBear do
  @moduledoc """
  vmangos `npc_rabid_thistle_bear`, the Darkshore bears trapped for "Plagued
  Lands" (2118).

  Tharnariun's Hope places a bear trap whose linked trap springs Bear
  Captured in Trap (9439) on the first hostile bear to walk over it. The bear
  becomes a friendly Captured Rabid Thistle Bear, credits the trapper with
  the capture the quest counts, drops combat, and follows the trapper until
  it disappears five minutes later.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @rabid_thistle_bear 2_164
  @captured_bear 11_836
  @bear_captured_in_trap 9_439
  @follow_motion 15
  @follow_distance 2.0
  @captured_ms 300_000

  @impl CreatureScript
  def entries, do: [@rabid_thistle_bear]

  @impl CreatureScript
  def events(@rabid_thistle_bear) do
    [
      CreatureScript.event(@rabid_thistle_bear, 1, :hit_by_spell, capture(),
        param1: @bear_captured_in_trap,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      )
    ]
  end

  defp capture do
    [
      %ScriptStep{command: :set_phase, datalong: 1},
      %ScriptStep{command: :update_entry, datalong: @captured_bear},
      %ScriptStep{command: :kill_credit, datalong: @captured_bear},
      %ScriptStep{command: :enter_evade},
      %ScriptStep{command: :movement, datalong: @follow_motion, position: {@follow_distance, 0.0, 0.0, :math.pi() / 2}},
      %ScriptStep{command: :despawn, datalong: @captured_ms}
    ]
  end
end
