defmodule ThistleTea.Game.Core.Power.PowerBurn do
  @moduledoc """
  Consumes the target's active power and converts the actual loss into spell
  damage. Absorption protects health without refunding the consumed resource.
  """
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Power.Resources
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Combat, as: SpellCombat
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Modifiers
  alias ThistleTea.Game.Core.Spell.ProcOrigin
  alias ThistleTea.Game.Core.Spell.SpellEffect.DamageHeal

  def apply(entity, %CastContext{} = context, %Spell{} = spell, amount, effect, now, opts \\ []) do
    if Entity.dead?(entity) do
      {entity, []}
    else
      {entity, consumed} = Resources.consume_power(entity, effect.misc_value, amount)

      if consumed > 0 do
        entity = damage_contact(entity, context, spell, now, opts)

        damage = trunc(consumed * multiplier(context, effect.multiple_value, opts))
        opts = Keyword.put(opts, :damage_effect, damage_effect(spell, effect))
        apply_damage(entity, context, spell, damage, now, opts)
      else
        {entity, []}
      end
    end
  end

  defp damage_effect(_spell, %Effect{} = effect), do: effect
  defp damage_effect(%Spell{effects: effects}, %Aura{index: index}), do: Enum.find(effects, &(&1.index == index))

  defp damage_contact(entity, context, spell, now, opts) do
    if SpellCombat.damage_contact?(spell, Keyword.get(opts, :periodic?, false), context.triggered_by_proc?),
      do: PlayerCombat.mark_hostile_contact(entity, context.caster_guid, now),
      else: entity
  end

  defp apply_damage(entity, context, spell, 0, _now, opts) do
    origin = if Keyword.get(opts, :periodic?, false), do: :cast, else: ProcOrigin.classify(spell, context)
    opts = Keyword.put(opts, :proc_origin, origin)
    {entity, [Effects.spell_damage(context.caster_guid, entity.object.guid, spell, 0, opts)]}
  end

  defp apply_damage(entity, context, spell, damage, now, opts) do
    DamageHeal.apply_damage_amount(entity, context, spell, damage, now, opts)
  end

  defp multiplier(context, multiple, opts) when is_number(multiple) do
    if Keyword.get(opts, :periodic?, false) do
      max(multiple, 0)
    else
      max(Modifiers.value(context.spell_modifiers, :multiple_value, multiple), 0)
    end
  end

  defp multiplier(_context, _multiple, _opts), do: 0
end
