defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.ScentOfLarkorwi do
  @moduledoc """
  vmangos `at_scent_larkorwi`: the sixteen triggers around Lar'korwi's lair
  in Un'Goro Crater call Lar'korwi's mate out for a player on The Scent of
  Lar'korwi (4291) whenever none is within 25 yards. She appears where the
  player stepped in and leaves after two minutes, or once she is killed and
  her corpse is gone.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @scent_of_larkorwi 4291
  @larkorwi_mate 9683
  @incomplete 1
  @facing 3.3
  @despawn_ms 120_000
  @unique_limit 1
  @unique_distance 25
  @unique 0x04
  @no_attack -1
  @timed_or_dead_despawn 1

  @impl AreaTriggerScript
  def triggers, do: Enum.to_list(1726..1740) ++ [1766]

  @impl AreaTriggerScript
  def steps(_trigger_id, {x, y, z}) do
    [
      %ScriptStep{
        command: :summon_creature,
        datalong: @larkorwi_mate,
        datalong2: @despawn_ms,
        datalong3: @unique_limit,
        datalong4: @unique_distance,
        dataint: @unique,
        dataint3: @no_attack,
        dataint4: @timed_or_dead_despawn,
        position: {x, y, z, @facing},
        condition: %Condition{type: :quest_taken, value1: @scent_of_larkorwi, value2: @incomplete}
      }
    ]
  end
end
