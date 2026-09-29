defmodule ThistleTea.Game.Core.Spell.SpellEffect.Reputation do
  @moduledoc false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect.Amount

  def apply(
        %Character{} = character,
        %CastContext{} = context,
        %Spell{} = spell,
        %Effect{type: :reputation, misc_value: faction_id} = effect,
        _now
      )
      when is_integer(faction_id) and faction_id > 0 do
    value = Amount.roll(spell, effect, context)
    {character, [Effects.reputation_change(faction_id, value)]}
  end

  def apply(entity, %CastContext{}, %Spell{}, %Effect{}, _now), do: {entity, []}
end
