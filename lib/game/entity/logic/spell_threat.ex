defmodule ThistleTea.Game.Entity.Logic.SpellThreat do
  @moduledoc """
  Projects a caster's current threat modifiers and applies them to spell damage
  and effective healing. Critical-threat modifiers affect damage spells only.
  """

  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Modifiers

  defstruct school_modifiers: [], critical_modifiers: [], spell_modifiers: [], healing_ratio: 0.5

  def projection(entity) do
    %__MODULE__{
      school_modifiers: Aura.misc_amounts(entity, :mod_threat),
      critical_modifiers: Aura.misc_amounts(entity, :mod_critical_threat),
      spell_modifiers: Enum.filter(Modifiers.snapshot_all(entity), &threat_modifier?/1),
      healing_ratio: healing_ratio(entity)
    }
  end

  def put_context(%CastContext{} = context, %Spell{} = spell, %__MODULE__{} = projection) do
    modifiers = Modifiers.for_spell(projection.spell_modifiers, spell)

    %{
      context
      | threat_multiplier:
          school_multiplier(projection.school_modifiers, spell) * Modifiers.value(modifiers, :threat, 100) / 100,
        critical_threat_multiplier: school_multiplier(projection.critical_modifiers, spell),
        healing_threat_ratio: projection.healing_ratio
    }
  end

  def multiplier(%CastContext{} = context, critical? \\ false) do
    critical = if critical?, do: context.critical_threat_multiplier, else: 1.0
    (context.threat_multiplier || 1.0) * critical * coefficient(context.spell_threat)
  end

  def heal_events(target, %CastContext{} = context, %Spell{} = spell, healing, opts \\ []) do
    ratio = if Keyword.get(opts, :periodic?, false), do: 0.5, else: context.healing_threat_ratio
    scaling = helpful_multiplier(context, spell) * ratio / Threat.heal_threat_ratio()
    Threat.heal_threat_events(target, context.caster_guid, healing, scaling)
  end

  def assist_events(target, %CastContext{} = context, %Spell{} = spell, gained) when gained > 0 do
    amount = gained * 0.5 * helpful_multiplier(context, spell)

    if amount > 0 and is_integer(context.caster_guid) and context.caster_guid > 0 do
      [Effects.heal_threat(context.caster_guid, target.object.guid, amount)]
    else
      []
    end
  end

  def assist_events(_target, _context, _spell, _gained), do: []

  defp helpful_multiplier(context, spell) do
    if Spell.attribute?(spell, :no_helpful_threat), do: 0.0, else: multiplier(context)
  end

  defp coefficient(%{multiplier: multiplier}) when is_number(multiplier), do: multiplier
  defp coefficient(_entry), do: 1.0

  defp school_multiplier(modifiers, spell) do
    mask = Spell.school_mask(spell)

    Enum.reduce(modifiers, 1.0, fn {school, amount}, multiplier ->
      if Bitwise.band(school, mask) == 0, do: multiplier, else: multiplier * max(100 + amount, 0) / 100
    end)
  end

  defp threat_modifier?({_family, aura}), do: Modifiers.operation(aura.misc_value) == :threat

  defp healing_ratio(%{unit: %{class: 2}}), do: 0.25
  defp healing_ratio(_entity), do: 0.5
end
