defmodule ThistleTea.Game.Entity.Logic.PowerBurn do
  @moduledoc """
  Consumes the target's active power and converts the actual loss into spell
  damage. Absorption protects health without refunding the consumed resource.
  """
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Modifiers

  def apply(entity, %CastContext{} = context, %Spell{} = spell, amount, effect, now, opts \\ []) do
    if Core.dead?(entity) do
      {entity, []}
    else
      {entity, consumed} = Resources.consume_power(entity, effect.misc_value, amount)
      damage = trunc(consumed * multiplier(context, effect.multiple_value, opts))

      if damage > 0 do
        DamageHeal.apply_damage_amount(entity, context, spell, damage, now, opts)
      else
        {entity, []}
      end
    end
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
