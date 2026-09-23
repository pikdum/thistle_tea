defmodule ThistleTea.Game.Spell.Requirements do
  @moduledoc "Pure cast requirements that depend on a current snapshot of nearby world objects."

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.Spell.ObjectTargets

  defstruct [:focus, :corpse, :objects]

  def required?(caster, %Spell{} = spell),
    do: Focus.required?(caster, spell) or CorpseTarget.required?(spell) or ObjectTargets.required?(spell)

  def validate(caster, spell, %__MODULE__{focus: focus, corpse: corpse, objects: objects}) do
    with :ok <- Focus.validate(caster, spell, focus),
         :ok <- CorpseTarget.validate(spell, corpse),
         do: ObjectTargets.validate(spell, objects)
  end
end
