defmodule ThistleTea.Game.Spell.Requirements do
  @moduledoc "Pure cast requirements that depend on a current snapshot of nearby world objects."

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Focus

  defstruct [:focus, :corpse]

  def required?(caster, %Spell{} = spell), do: Focus.required?(caster, spell) or CorpseTarget.required?(spell)

  def validate(caster, spell, %__MODULE__{focus: focus, corpse: corpse}) do
    with :ok <- Focus.validate(caster, spell, focus), do: CorpseTarget.validate(spell, corpse)
  end
end
