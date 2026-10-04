defmodule ThistleTea.Game.Core.AI.CreatureScript.Belnistrasz do
  @moduledoc """
  vmangos `npc_belnistrasz`, the Argent Dawn mage held in Razorfen Downs,
  whose escort and idol ritual are a quest escort (`QuestEscort.Catalog`,
  Extinguishing the Idol).

  On the way to the idol he fights with Fireball and Frost Nova. While he
  chants the idol quiet he stops fighting, and the first time he is struck
  he cries out to the party. vmangos keeps him in the fight for the whole
  chant, where he drops out of it as each wave dies, which ends his channel,
  so he takes the channel up again.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @belnistrasz 8_516
  @fireball 9_053
  @frost_nova 11_831
  @idol_shutdown 12_774
  @chanting 1
  @warned 2

  @impl CreatureScript
  def entries, do: [@belnistrasz]

  @impl CreatureScript
  def events(@belnistrasz = entry) do
    fighting = CreatureScript.only_in_phases([0])

    [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast_victim(@fireball)],
        param1: 1_000,
        param2: 1_000,
        param3: 2_000,
        param4: 3_000,
        inverse_phase_mask: fighting,
        not_casting?: true
      ),
      CreatureScript.event(entry, 2, :timer_in_combat, [cast_victim(@frost_nova)],
        param1: 6_000,
        param2: 6_000,
        param3: 10_000,
        param4: 15_000,
        inverse_phase_mask: fighting,
        not_casting?: true
      ),
      CreatureScript.event(
        entry,
        3,
        :aggro,
        [
          %ScriptStep{command: :talk, dataint: 9_008, dataint2: 9_007},
          %ScriptStep{command: :set_phase, datalong: @warned}
        ],
        inverse_phase_mask: CreatureScript.only_in_phases([@chanting])
      ),
      CreatureScript.event(
        entry,
        4,
        :evade,
        [%ScriptStep{command: :cast_spell, datalong: @idol_shutdown, target_self?: true}],
        inverse_phase_mask: CreatureScript.only_in_phases([@chanting, @warned])
      )
    ]
  end

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}
end
