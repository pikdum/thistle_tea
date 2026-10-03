defmodule ThistleTea.Game.Core.AI.GameObjectScript do
  @moduledoc """
  Ports of vmangos C++ game object scripts, the `GOHello` hooks behind a
  `gameobject_template` `script_name`, written as generic script steps. The
  steps run when a player uses the object: on that player, with the object as
  their target, so their conditions read around the object and their summons
  can attack the player who used it.

  vmangos runs the hook before the object's own use, and a hook that claims
  the use stops it there. A port only adds steps, and the object still opens,
  locks out, and runs its database script as usual, so a claimed use that
  vmangos keeps open for minutes instead closes on its template's timer. A
  script receives the position of the object that was used, so one script can
  serve every spawn of its entries.
  """

  alias ThistleTea.Game.Core.AI.GameObjectScript.HandOfIruxosCrystal
  alias ThistleTea.Game.Core.AI.GameObjectScript.InconspicuousLandmark
  alias ThistleTea.Game.Core.AI.GameObjectScript.LardsPicnicBasket
  alias ThistleTea.Game.Core.AI.GameObjectScript.PantherCage
  alias ThistleTea.Game.Core.AI.GameObjectScript.ResoniteCask
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep

  @callback entries() :: [pos_integer()]
  @callback steps(pos_integer(), {number(), number(), number(), number()}) :: [%ScriptStep{}]

  @scripts [
    HandOfIruxosCrystal,
    InconspicuousLandmark,
    LardsPicnicBasket,
    PantherCage,
    ResoniteCask
  ]
  @origin {0.0, 0.0, 0.0, 0.0}

  def ported?(entry), do: not is_nil(script(entry))

  def steps(entry, {_x, _y, _z, _o} = position) when is_integer(entry) do
    case script(entry) do
      nil -> []
      script -> script.steps(entry, position)
    end
  end

  def entries, do: Enum.flat_map(@scripts, & &1.entries())

  def summon_entries do
    entries()
    |> Enum.flat_map(&steps(&1, @origin))
    |> Script.summon_entries()
  end

  defp script(entry), do: Enum.find(@scripts, &(entry in &1.entries()))
end
