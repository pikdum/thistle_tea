defmodule ThistleTea.Game.Core.Environment.LiquidSpells do
  @moduledoc "Reconciles liquid-granted spells through normal spell application and aura removal."

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.SpellEffect

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
