defmodule ThistleTea.Game.Core.AI.GameObjectScript do
  @moduledoc """
  Ports of vmangos C++ game object scripts, the hooks behind a
  `gameobject_template` `script_name`, written as generic script steps.

  `steps/2` ports `GOHello`: the steps run when a player uses the object, on
  that player, with the object as their target, so their conditions read
  around the object and their summons can attack the player who used it.
  vmangos runs the hook before the object's own use, and a hook that claims
  the use stops it there. A port only adds steps, and the object still opens,
  locks out, and runs its database script as usual, so a claimed use that
  vmangos keeps open for minutes instead closes on its template's timer.

  `activated/3` ports `OnActivateBySpell` for the spells a script lists in
  `spells/0`. When one of them reaches the object through an activate object
  effect, the claim's steps run on the caster, with the caster as their
  target, and the claim's object action replaces the spell's own.

  A script receives the position of the object, so one script can serve every
  spawn of its entries.
  """

  alias ThistleTea.Game.Core.AI.GameObjectScript.HandOfIruxosCrystal
  alias ThistleTea.Game.Core.AI.GameObjectScript.InconspicuousLandmark
  alias ThistleTea.Game.Core.AI.GameObjectScript.LardsPicnicBasket
  alias ThistleTea.Game.Core.AI.GameObjectScript.PantherCage
  alias ThistleTea.Game.Core.AI.GameObjectScript.ResoniteCask
  alias ThistleTea.Game.Core.AI.GameObjectScript.WindStone
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep

  @type position :: {number(), number(), number(), number()}

  @callback entries() :: [pos_integer()]
  @callback steps(pos_integer(), position()) :: [%ScriptStep{}]
  @callback spells() :: [pos_integer()]
  @callback activated(pos_integer(), pos_integer(), position()) :: {[%ScriptStep{}], non_neg_integer()}
  @optional_callbacks steps: 2, spells: 0, activated: 3

  @scripts [
    HandOfIruxosCrystal,
    InconspicuousLandmark,
    LardsPicnicBasket,
    PantherCage,
    ResoniteCask,
    WindStone
  ]
  @origin {0.0, 0.0, 0.0, 0.0}

  def ported?(entry), do: not is_nil(script(entry))

  def steps(entry, {_x, _y, _z, _o} = position) when is_integer(entry) do
    case script(entry, :steps, 2) do
      nil -> []
      script -> script.steps(entry, position)
    end
  end

  def activated(entry, spell_id, {_x, _y, _z, _o} = position) when is_integer(entry) and is_integer(spell_id) do
    case script(entry, :activated, 3) do
      nil -> :pass
      script -> if spell_id in script.spells(), do: claim(script.activated(entry, spell_id, position)), else: :pass
    end
  end

  def entries, do: Enum.flat_map(@scripts, & &1.entries())

  def summon_entries do
    entries()
    |> Enum.flat_map(fn entry -> steps(entry, @origin) ++ activation_steps(entry) end)
    |> Script.summon_entries()
  end

  defp claim({steps, action}) when is_list(steps) and is_integer(action), do: {:claim, steps, action}

  defp activation_steps(entry) do
    case script(entry, :activated, 3) do
      nil -> []
      script -> Enum.flat_map(script.spells(), &elem(script.activated(entry, &1, @origin), 0))
    end
  end

  defp script(entry), do: Enum.find(@scripts, &(entry in &1.entries()))

  defp script(entry, callback, arity) do
    with script when not is_nil(script) <- script(entry),
         true <- Code.ensure_loaded?(script) and function_exported?(script, callback, arity) do
      script
    else
      _missing -> nil
    end
  end
end
