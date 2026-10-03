defmodule ThistleTea.Game.Core.AI.CreatureScript.Faulk do
  @moduledoc """
  vmangos `npc_henze_faulk` and `npc_narm_faulk`, the fallen paladins that
  Human and Dwarf paladins raise for "The Tome of Divinity" (1786 and 1783).

  Both spawn dead. Symbol of Life (8593) brings one back to life for two
  minutes, long enough to finish the quest, and he thanks the paladin who
  raised him before lying back down.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @henze_faulk 6172
  @narm_faulk 6177
  @symbol_of_life 8593
  @thanks 2281

  @impl CreatureScript
  def entries, do: [@henze_faulk, @narm_faulk]

  @impl CreatureScript
  def events(entry) do
    [
      CreatureScript.event(entry, 1, :hit_by_spell, [%ScriptStep{command: :talk, dataint: @thanks}],
        param1: @symbol_of_life
      )
    ]
  end
end
