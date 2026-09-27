defmodule ThistleTea.Game.Spell.Requirements do
  @moduledoc "Pure cast requirements that depend on current terrain, target positions, and nearby world objects."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.AuraRank
  alias ThistleTea.Game.Spell.CastTarget
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Environment
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.Spell.LocationTargets
  alias ThistleTea.Game.Spell.ObjectTargets
  alias ThistleTea.Game.Spell.UnitTargets

  defstruct [:focus, :corpse, :objects, :units, :locations, :aura_target, :cast_target, :spell_area, :outdoors?]

  def required?(caster, %Spell{} = spell, opts \\ []),
    do:
      Focus.required?(caster, spell) or CorpseTarget.required?(spell) or ObjectTargets.required?(spell) or
        target_required?(caster, spell, opts) or Area.restricted?(spell) or
        (match?(%Character{}, caster) and Environment.restricted?(spell))

  defp target_required?(caster, spell, opts) do
    UnitTargets.required?(spell) or LocationTargets.required?(spell) or
      AuraRank.requires_check?(caster, spell, opts) or CastTarget.required?(caster, spell, opts)
  end

  def validate(
        caster,
        spell,
        %__MODULE__{
          focus: focus,
          corpse: corpse,
          objects: objects,
          units: units,
          locations: locations,
          aura_target: target,
          cast_target: cast_target,
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
         :ok <- CastTarget.validate(caster, spell, cast_target, opts),
         :ok <- ObjectTargets.validate(spell, objects),
         :ok <- LocationTargets.validate(spell, locations),
         do: UnitTargets.validate(spell, units)
  end
end
