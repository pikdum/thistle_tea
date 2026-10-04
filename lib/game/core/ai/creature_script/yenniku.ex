defmodule ThistleTea.Game.Core.AI.CreatureScript.Yenniku do
  @moduledoc """
  vmangos `mob_yenniku`, the Darkspear hostage held by Zanzil the Outcast at
  the Ruins of Aboraz for "Saving Yenniku" (592).

  Yenniku's Release (3607) is the Soul Gem's spell. When it hits him from a
  player still on the quest, he is stunned, stops fighting, and turns Horde
  friendly. The player can then hand him the gem to fill it with his soul
  ("Filling the Soul Gem", 593). A minute later he shakes it off, evades, and
  rejoins the Bloodscalps.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @yenniku 2_530
  @saving_yenniku 592
  @incomplete 1
  @yenniku_release 3_607
  @horde_generic 83
  @stun_state 64
  @no_state 0
  @stunned_ms 60_000

  @impl CreatureScript
  def entries, do: [@yenniku]

  @impl CreatureScript
  def events(@yenniku) do
    [
      CreatureScript.event(@yenniku, 1, :hit_by_spell, stun(),
        param1: @yenniku_release,
        inverse_phase_mask: CreatureScript.only_in_phases([0]),
        condition: %Condition{type: :quest_taken, value1: @saving_yenniku, value2: @incomplete}
      ),
      CreatureScript.event(@yenniku, 2, :evade, [%ScriptStep{command: :emote, datalong: @no_state}])
    ]
  end

  defp stun do
    [
      %ScriptStep{command: :set_phase, datalong: 1},
      %ScriptStep{command: :emote, datalong: @stun_state},
      %ScriptStep{command: :combat_stop},
      CreatureScript.faction(@horde_generic),
      CreatureScript.timed([
        %ScriptStep{command: :set_faction, datalong: 0, delay_ms: @stunned_ms},
        %ScriptStep{command: :enter_evade, delay_ms: @stunned_ms},
        %ScriptStep{command: :set_phase, datalong: 0, delay_ms: @stunned_ms}
      ])
    ]
  end
end
