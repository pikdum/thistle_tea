defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Inventory do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Durability
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  def apply(state, %CastContext{} = context, spell, %Effect{type: :create_item, misc_value: item_id} = effect, _now)
      when is_integer(item_id) and item_id > 0 do
    count = max(Amount.roll(spell, effect, context), 1)
    {state, [%{Effects.create_item(item_id, count) | spell_id: spell.id}]}
  end

  def apply(%Character{} = state, %CastContext{} = context, spell, %Effect{type: type} = effect, _now)
      when type in [:durability_damage, :durability_damage_percent] do
    case Durability.spell_scope(effect.misc_value) do
      nil ->
        {state, []}

      scope ->
        {state,
         [
           %Effects.DurabilityLoss{
             target_guid: state.object.guid,
             mode: if(type == :durability_damage, do: :points, else: :percent),
             amount: Amount.roll(spell, effect, context),
             scope: scope,
             caster_guid: context.caster_guid,
             spell_id: spell.id
           }
         ]}
    end
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}
end
