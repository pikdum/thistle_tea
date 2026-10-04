defmodule ThistleTea.Game.Core.AI.CreatureScript.Emberstrife do
  @moduledoc """
  vmangos `npc_emberstrife`, the black dragon in the Wyrmbog whose flame
  forges the Seal of Ascension (4743).

  He cleaves and breathes fire at his victim. Below 60 percent health he
  goes into a killing frenzy, and again every two minutes after that. Below
  11 percent he is weakened, the moment a player can take control of him
  with the Orb of Draconic Energy and turn his Flames of the Black Flight on
  the Unforged Seal.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @emberstrife 10_321

  @cleave 19_983
  @flame_breath 9_573
  @frenzy 8_269

  @killing_frenzy 7_797
  @weakened 11_476

  @frenzy_health 60
  @weakened_health 11
  @frenzy_ms 120_500

  @impl CreatureScript
  def entries, do: [@emberstrife]

  @impl CreatureScript
  def events(@emberstrife) do
    [
      CreatureScript.event(@emberstrife, 1, :timer_in_combat, [cast_victim(@cleave)], timer({6_000, 8_000})),
      CreatureScript.event(@emberstrife, 2, :timer_in_combat, [cast_victim(@flame_breath)], timer({8_000, 12_000})),
      CreatureScript.event(
        @emberstrife,
        3,
        :hp,
        [%ScriptStep{command: :cast_spell, datalong: @frenzy, target_self?: true}, talk(@killing_frenzy)],
        param1: @frenzy_health,
        param3: @frenzy_ms,
        param4: @frenzy_ms
      ),
      CreatureScript.event(@emberstrife, 4, :hp, [talk(@weakened)], param1: @weakened_health, repeatable?: false)
    ]
  end

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}

  defp timer({min_ms, max_ms}), do: [param1: min_ms, param2: max_ms, param3: min_ms, param4: max_ms]
end
