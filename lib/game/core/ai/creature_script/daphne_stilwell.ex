defmodule ThistleTea.Game.Core.AI.CreatureScript.DaphneStilwell do
  @moduledoc """
  vmangos `npc_daphne_stilwell`'s cheers through Tome of Valor (1651) in
  Westfall. Her run to the house, the three Defias waves, and the walk back
  to the orchard are an escort in the quest escort catalog, which marks each
  wave with an EventAI phase. Once a wave is beaten she cheers it: the first
  and second with a quip, the third as the victory.

  She fights the raiders in melee instead of trading rifle shots with them
  from range, and her rifle stays out of sight.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @daphne 6_182
  @showed_that_one 5_269
  @one_more_down 2_369
  @we_won 2_358
  @between_waves 0

  @impl CreatureScript
  def entries, do: [@daphne]

  @impl CreatureScript
  def events(@daphne) do
    Enum.map([{1, @showed_that_one}, {2, @one_more_down}, {3, @we_won}], fn {wave, text_id} ->
      CreatureScript.event(
        @daphne,
        wave,
        :evade,
        [%ScriptStep{command: :talk, dataint: text_id}, %ScriptStep{command: :set_phase, datalong: @between_waves}],
        inverse_phase_mask: CreatureScript.only_in_phases([wave])
      )
    end)
  end
end
