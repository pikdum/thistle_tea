defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.TwiggyFlathead do
  @moduledoc """
  vmangos `at_twiggy_flathead`: a living player stepping into the Barrens
  ring with The Affray (1719) unfinished tells Twiggy Flathead to start the
  fight, which `CreatureScript.TwiggyFlathead` runs. The ring's quest
  exploration credit comes from the trigger's quest relation as usual.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.CreatureScript.TwiggyFlathead, as: Twiggy
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @ring 522
  @affray 1719
  @twiggy 6248
  @incomplete 1
  @call_radius 30
  @call_script 1

  @impl AreaTriggerScript
  def triggers, do: [@ring]

  @impl AreaTriggerScript
  def steps(_trigger_id, _position) do
    [
      %ScriptStep{
        command: :start_script,
        datalong: @call_script,
        dataint: 100,
        sub_scripts: %{@call_script => [call_twiggy()]},
        condition: %Condition{type: :quest_taken, value1: @affray, value2: @incomplete}
      }
    ]
  end

  defp call_twiggy do
    %ScriptStep{
      command: :send_script_event,
      datalong: Twiggy.begin_event(),
      target_type: :nearest_creature_with_entry,
      target_param1: @twiggy,
      target_param2: @call_radius,
      swap_final?: true
    }
  end
end
