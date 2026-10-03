defmodule ThistleTea.Game.Core.AI.CreatureScript.MagramiSpectre do
  @moduledoc """
  vmangos `npc_magrami_spetre`, the spirits a Ghost Magnet calls for
  Ghost-o-plasm Round Up (6134) in Desolace.

  A spectre drifts in wrapped in blue spirit particles, harmless to all,
  until it reaches the magnet it was called to. There its particles turn
  green and it turns on anyone near, laying the Curse of the Fallen Magram
  on its foe when the foe is not already cursed. A spectre that gives up a
  fight drifts back to the magnet and stays hostile.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @spectre 11_560
  @blue_particles 17_327
  @green_particles 18_951
  @curse_of_the_fallen_magram 18_159
  @hostile 16
  @point_motion 9
  @magnet_point 2
  @aura_not_present 0x20

  @impl CreatureScript
  def entries, do: [@spectre]

  @impl CreatureScript
  def events(@spectre = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [%ScriptStep{command: :add_aura, datalong: @blue_particles}]),
      CreatureScript.event(entry, 2, :movement_inform, turn_green(), param1: @point_motion, param2: @magnet_point),
      CreatureScript.event(entry, 3, :reached_home, turn_green()),
      CreatureScript.event(entry, 4, :timer_in_combat, [curse()],
        param1: 5_000,
        param2: 9_000,
        param3: 15_000,
        param4: 21_000
      )
    ]
  end

  defp turn_green do
    [
      %ScriptStep{command: :remove_aura, datalong: @blue_particles},
      %ScriptStep{command: :add_aura, datalong: @green_particles},
      CreatureScript.faction(@hostile)
    ]
  end

  defp curse do
    %ScriptStep{
      command: :cast_spell,
      datalong: @curse_of_the_fallen_magram,
      datalong2: @aura_not_present,
      target_type: :victim
    }
  end
end
