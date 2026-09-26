defmodule ThistleTea.Game.Entity.Logic.LiquidSpells do
  @moduledoc "Reconciles liquid-granted spells through normal spell application and aura removal."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  def active?(%Character{internal: %Internal{liquid_spell_id: id}}), do: is_integer(id)
  def active?(_entity), do: false

  def reconcile(%Character{} = character, context, now) do
    context = if Death.alive?(character), do: context
    id = spell_id(context)
    character = remove_previous(character, id, now)
    character = %{character | internal: %{character.internal | liquid_spell_id: id}}
    apply_missing(character, context, now)
  end

  def reconcile(entity, _context, _now), do: entity

  defp spell_id(%CastContext{spell: %Spell{id: id}}), do: id
  defp spell_id(_context), do: nil

  defp remove_previous(%Character{internal: %Internal{liquid_spell_id: previous}} = character, id, now)
       when is_integer(previous) and previous != id do
    {character, events} = Aura.remove_spells(character, [previous], now)
    Effects.enqueue(character, events)
  end

  defp remove_previous(character, _id, _now), do: character

  defp apply_missing(character, %CastContext{spell: %Spell{} = spell} = context, now) do
    if Aura.has_spell?(character, spell.id) do
      character
    else
      {character, events} = SpellEffect.receive(character, context, spell, now)
      Effects.enqueue(character, events)
    end
  end

  defp apply_missing(character, _context, _now), do: character
end
