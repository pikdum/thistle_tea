defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.Ravenholdt do
  @moduledoc """
  vmangos `at_ravenholdt`: reaching Ravenholdt Manor's courtyard counts as
  finding the manor for a rogue on The Manor, Ravenholdt (6681), whose
  objective is a kill credit for the Ravenholdt marker creature.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @courtyard 3066
  @manor_ravenholdt 6681
  @ravenholdt 13_936
  @incomplete 1

  @impl AreaTriggerScript
  def triggers, do: [@courtyard]

  @impl AreaTriggerScript
  def steps(_trigger_id, _position) do
    [
      %ScriptStep{
        command: :kill_credit,
        datalong: @ravenholdt,
        condition: %Condition{type: :quest_taken, value1: @manor_ravenholdt, value2: @incomplete}
      }
    ]
  end
end
