defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.ChildrensWeek do
  @moduledoc """
  vmangos `at_childrens_week_spot`: the Children's Week sights an orphan asks
  to see. Bringing the right orphan along completes its visit: the Human
  Orphan's Bough of the Eternals (1479), Stonewrought Dam (1558), and Spooky
  Lighthouse (1687), and the Orcish Orphan's Lordaeron Throne Room (1800),
  Gateway to the Frontier (911), and Down at the Docks (910).
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @human_orphan 14_305
  @orcish_orphan 14_444

  @sights %{
    3546 => {@human_orphan, 1479},
    3547 => {@orcish_orphan, 1800},
    3548 => {@human_orphan, 1558},
    3549 => {@orcish_orphan, 911},
    3550 => {@orcish_orphan, 910},
    3552 => {@human_orphan, 1687}
  }

  @impl AreaTriggerScript
  def triggers, do: Map.keys(@sights)

  @impl AreaTriggerScript
  def steps(trigger_id, _position) do
    {orphan, quest_id} = Map.fetch!(@sights, trigger_id)

    [
      %ScriptStep{
        command: :quest_explored,
        datalong: quest_id,
        condition: %Condition{type: :mini_pet, value1: orphan}
      }
    ]
  end
end
