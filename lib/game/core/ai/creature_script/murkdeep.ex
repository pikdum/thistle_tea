defmodule ThistleTea.Game.Core.AI.CreatureScript.Murkdeep do
  @moduledoc """
  vmangos `npc_murkdeep`'s fighting: Murkdeep sunders his target's armor every
  five to nine seconds and throws a net every nine to fifteen, and flees once
  when he falls below fifteen percent health. The murloc camp area trigger
  calls him out for WANTED: Murkdeep! and runs his waves.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @murkdeep 10_323
  @sunder_armor 11_971
  @net 6_533
  @flee_pct 15

  @impl CreatureScript
  def entries, do: [@murkdeep]

  @impl CreatureScript
  def events(@murkdeep) do
    [
      CreatureScript.event(@murkdeep, 1, :timer_in_combat, [cast_victim(@sunder_armor)],
        param1: 0,
        param2: 5_000,
        param3: 5_000,
        param4: 9_000
      ),
      CreatureScript.event(@murkdeep, 2, :timer_in_combat, [cast_victim(@net)],
        param1: 0,
        param2: 20_000,
        param3: 9_000,
        param4: 15_000
      ),
      CreatureScript.event(@murkdeep, 3, :hp, [%ScriptStep{command: :flee}],
        param1: @flee_pct,
        param2: 0,
        repeatable?: false
      )
    ]
  end

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}
end
