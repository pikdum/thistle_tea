defmodule ThistleTea.Game.Core.AI.AreaTriggerScript do
  @moduledoc """
  Ports of vmangos C++ area trigger scripts, the `script_name` scripts of
  `areatrigger_template`, written as generic script steps. The steps run on
  the player who stepped inside, with that player as their target, so their
  conditions read the player's quest log and class.

  vmangos runs a trigger's C++ script instead of its database script, so a
  ported trigger replaces any `areatrigger_scripts` rows. A script receives
  the position of the trigger that fired, so one script can serve several
  triggers and act where the player stands.
  """

  alias ThistleTea.Game.Core.AI.AreaTriggerScript.HuldarMiran
  alias ThistleTea.Game.Core.AI.AreaTriggerScript.IrontreeWood
  alias ThistleTea.Game.Core.AI.AreaTriggerScript.Ravenholdt
  alias ThistleTea.Game.Core.AI.AreaTriggerScript.ScentOfLarkorwi
  alias ThistleTea.Game.Core.AI.AreaTriggerScript.SentryPoint
  alias ThistleTea.Game.Core.AI.AreaTriggerScript.TwiggyFlathead
  alias ThistleTea.Game.Core.AI.AreaTriggerScript.TwilightGrove
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep

  @callback triggers() :: [pos_integer()]
  @callback steps(pos_integer(), {number(), number(), number()}) :: [%ScriptStep{}]

  @scripts [HuldarMiran, IrontreeWood, Ravenholdt, ScentOfLarkorwi, SentryPoint, TwiggyFlathead, TwilightGrove]
  @origin {0.0, 0.0, 0.0}

  def ported?(trigger_id), do: not is_nil(script(trigger_id))

  def steps(trigger_id, {_x, _y, _z} = position) when is_integer(trigger_id) do
    case script(trigger_id) do
      nil -> nil
      script -> script.steps(trigger_id, position)
    end
  end

  def triggers, do: Enum.flat_map(@scripts, & &1.triggers())

  def summon_entries do
    triggers()
    |> Enum.flat_map(&steps(&1, @origin))
    |> Script.summon_entries()
  end

  defp script(trigger_id), do: Enum.find(@scripts, &(trigger_id in &1.triggers()))
end
