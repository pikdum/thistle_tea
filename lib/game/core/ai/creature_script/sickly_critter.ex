defmodule ThistleTea.Game.Core.AI.CreatureScript.SicklyCritter do
  @moduledoc """
  vmangos `npc_sickly_critter`, the sickly deer and gazelles that druids cure
  for "Curing the Sick" (6124 and 6129).

  Apply Salve (19512) makes the critter flee from the druid and despawn ten
  seconds later. After a second and a half it becomes its cured entry and
  loses the Sickly Critter aura (19502). The druid then gets cast credit
  against the cured entry, which is what the quests count.

  vmangos picks the cured entry by the druid's team, so an Alliance druid
  turns a gazelle into a cured deer. Here each sickly critter keeps its own
  species.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @cured %{12_296 => 12_297, 12_298 => 12_299}
  @apply_salve 19_512
  @sickly_aura 19_502
  @cure_ms 1_500
  @despawn_ms 10_000
  @fleeing_motion 10

  @impl CreatureScript
  def entries, do: Map.keys(@cured)

  @impl CreatureScript
  def events(entry) do
    [
      CreatureScript.event(entry, 1, :hit_by_spell, cure(Map.fetch!(@cured, entry)),
        param1: @apply_salve,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      )
    ]
  end

  defp cure(cured_entry) do
    [
      %ScriptStep{command: :set_phase, datalong: 1},
      %ScriptStep{command: :movement, datalong: @fleeing_motion, datalong3: @despawn_ms},
      %ScriptStep{command: :despawn, datalong: @despawn_ms},
      CreatureScript.timed([
        %ScriptStep{command: :update_entry, datalong: cured_entry, delay_ms: @cure_ms},
        %ScriptStep{command: :remove_aura, datalong: @sickly_aura, delay_ms: @cure_ms},
        %ScriptStep{command: :cast_credit, datalong: @apply_salve, delay_ms: @cure_ms}
      ])
    ]
  end
end
