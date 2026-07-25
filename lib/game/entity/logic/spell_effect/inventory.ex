defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Inventory do
  @moduledoc false

  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  def apply(state, %CastContext{} = context, spell, %Effect{type: :create_item, misc_value: item_id} = effect, _now)
      when is_integer(item_id) and item_id > 0 do
    count = max(Amount.roll(spell, effect, context), 1)
    {state, [Effects.create_item(item_id, count)]}
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}
end
