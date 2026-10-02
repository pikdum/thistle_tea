defmodule ThistleTea.Game.Core.AI.CreatureScript.FelwoodOoze do
  @moduledoc """
  vmangos `npc_cursed_ooze` and `npc_tainted_ooze` (Felwood), whose remains
  fill the jars for "A Little Slime Goes a Long Way" (4512).

  Filling Empty Jar works on the ooze's corpse, and the corpse despawns once
  it has been jarred, so each kill fills one jar. In combat, each ooze casts
  its own aura three seconds after the pull and every minute after that.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @cursed_ooze 7_086
  @tainted_ooze 7_092
  @jars %{@cursed_ooze => 15_698, @tainted_ooze => 15_699}
  @auras %{@cursed_ooze => 13_483, @tainted_ooze => 3_335}
  @first_aura_ms 3_000
  @aura_repeat_ms 60_000

  @impl CreatureScript
  def entries, do: [@cursed_ooze, @tainted_ooze]

  @impl CreatureScript
  def events(entry) do
    aura = %ScriptStep{command: :cast_spell, datalong: Map.fetch!(@auras, entry), target_self?: true}

    [
      CreatureScript.event(entry, 1, :timer_in_combat, [aura],
        param1: @first_aura_ms,
        param2: @first_aura_ms,
        param3: @aura_repeat_ms,
        param4: @aura_repeat_ms
      ),
      CreatureScript.event(entry, 2, :hit_by_spell, [%ScriptStep{command: :despawn}], param1: Map.fetch!(@jars, entry))
    ]
  end
end
