defmodule ThistleTea.Game.Spell.Requirements do
  @moduledoc "Pure cast requirements that depend on a current snapshot of nearby world objects."

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.AuraRank
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.Spell.ObjectTargets

  defstruct [:focus, :corpse, :objects, :aura_target, :spell_area]

  def required?(caster, %Spell{} = spell, opts \\ []),
    do:
      Focus.required?(caster, spell) or CorpseTarget.required?(spell) or ObjectTargets.required?(spell) or
        AuraRank.requires_check?(caster, spell, opts) or Area.restricted?(spell)

  def validate(
        caster,
        spell,
        %__MODULE__{focus: focus, corpse: corpse, objects: objects, aura_target: target, spell_area: area},
        opts \\ []
      ) do
    with :ok <- Focus.validate(caster, spell, focus),
         :ok <- Area.validate(spell, area),
         :ok <- CorpseTarget.validate(spell, corpse),
         :ok <- AuraRank.validate(caster, spell, target, opts),
         do: ObjectTargets.validate(spell, objects)
  end
end
