defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Reputation do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

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
