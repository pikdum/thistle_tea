defmodule ThistleTea.Game.Core.Spell.Requirements do
  @moduledoc "Pure cast requirements that depend on current terrain, target positions, and nearby world objects."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Area
  alias ThistleTea.Game.Core.Spell.AuraRank
  alias ThistleTea.Game.Core.Spell.CastTarget
  alias ThistleTea.Game.Core.Spell.CorpseTarget
  alias ThistleTea.Game.Core.Spell.Environment
  alias ThistleTea.Game.Core.Spell.Focus
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.Mount
  alias ThistleTea.Game.Core.Spell.ObjectTargets
  alias ThistleTea.Game.Core.Spell.UnitTargets

  defstruct [
    :focus,
    :corpse,
    :objects,
    :units,
    :locations,
    :aura_target,
    :cast_target,
    :spell_area,
    :outdoors?,
    :mount_context
  ]

  def required?(caster, %Spell{} = spell, opts \\ []),
    do:
      Focus.required?(caster, spell) or CorpseTarget.required?(spell) or ObjectTargets.required?(spell) or
        target_required?(caster, spell, opts) or Area.restricted?(spell) or
        (match?(%Character{}, caster) and (Environment.restricted?(spell) or Mount.spell?(spell)))

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
          outdoors?: outdoors,
          mount_context: mount
        },
        opts \\ []
      ) do
    with :ok <- Focus.validate(caster, spell, focus),
         :ok <- Area.validate(spell, area),
         :ok <- Environment.validate(caster, spell, outdoors),
         :ok <- validate_mount(caster, spell, mount, opts),
         :ok <- CorpseTarget.validate(spell, corpse),
         :ok <- AuraRank.validate(caster, spell, target, opts),
         :ok <- CastTarget.validate(caster, spell, cast_target, opts),
         :ok <- ObjectTargets.validate(spell, objects),
         :ok <- LocationTargets.validate(spell, locations),
         do: UnitTargets.validate(spell, units)
  end

  defp validate_mount(caster, spell, %Mount.Context{} = context, opts),
    do: Mount.validate(caster, spell, Keyword.put(opts, :mount_context, context))

  defp validate_mount(_caster, _spell, _context, _opts), do: :ok
end
