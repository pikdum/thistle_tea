defmodule ThistleTea.Game.Spell.Requirements do
  @moduledoc "Pure cast requirements that depend on current terrain and nearby world objects."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.AuraRank
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Environment
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.Spell.ObjectTargets

  defstruct [:focus, :corpse, :objects, :aura_target, :spell_area, :outdoors?]

  def required?(caster, %Spell{} = spell, opts \\ []),
    do:
      Focus.required?(caster, spell) or CorpseTarget.required?(spell) or ObjectTargets.required?(spell) or
        AuraRank.requires_check?(caster, spell, opts) or Area.restricted?(spell) or
        (match?(%Character{}, caster) and Environment.restricted?(spell))

  def validate(
        caster,
        spell,
        %__MODULE__{
          focus: focus,
          corpse: corpse,
          objects: objects,
          aura_target: target,
          spell_area: area,
          outdoors?: outdoors
        },
        opts \\ []
      ) do
    with :ok <- Focus.validate(caster, spell, focus),
         :ok <- Area.validate(spell, area),
         :ok <- Environment.validate(caster, spell, outdoors),
         :ok <- CorpseTarget.validate(spell, corpse),
         :ok <- AuraRank.validate(caster, spell, target, opts),
         do: ObjectTargets.validate(spell, objects)
  end
end
