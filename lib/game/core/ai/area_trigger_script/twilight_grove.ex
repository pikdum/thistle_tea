defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.TwilightGrove do
  @moduledoc """
  vmangos `at_twilight_grove`: a living player entering the Twilight Grove
  in Duskwood with The Nightmare's Corruption (8735) unfinished draws out
  the Twilight Corrupter. The nearest Corrupter within 350 yards whispers
  to the player, or one rises at the grove's heart and whispers when none
  is about. A summoned Corrupter stays until it is killed.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @grove 4017
  @nightmares_corruption 8735
  @corrupter 15_625
  @come_see_the_nightmare 11_271
  @whisper 4
  @incomplete 1
  @call_radius 350
  @unique_limit 1
  @unique 0x04
  @no_attack -1
  @dead_despawn 7
  @nightmare_script 1
  @arrival_script 1

  @arrival {-10_335.9, -489.051, 50.6233, 2.59373}

  @impl AreaTriggerScript
  def triggers, do: [@grove]

  @impl AreaTriggerScript
  def steps(_trigger_id, _position) do
    [
      %ScriptStep{
        command: :start_script,
        datalong: @nightmare_script,
        dataint: 100,
        sub_scripts: %{@nightmare_script => [corrupter_whispers(), summon_corrupter()]},
        condition: %Condition{type: :quest_taken, value1: @nightmares_corruption, value2: @incomplete}
      }
    ]
  end

  defp corrupter_whispers do
    %{
      whisper()
      | target_type: :nearest_creature_with_entry,
        target_param1: @corrupter,
        target_param2: @call_radius,
        swap_final?: true
    }
  end

  defp summon_corrupter do
    %ScriptStep{
      command: :summon_creature,
      datalong: @corrupter,
      datalong3: @unique_limit,
      datalong4: @call_radius,
      dataint: @unique,
      dataint2: @arrival_script,
      dataint3: @no_attack,
      dataint4: @dead_despawn,
      position: @arrival,
      sub_scripts: %{@arrival_script => [whisper()]}
    }
  end

  defp whisper, do: %ScriptStep{command: :talk, datalong: @whisper, dataint: @come_see_the_nightmare}
end
