defmodule ThistleTea.Game.Entity.Logic.SpellEnvironment do
  @moduledoc "Reconciles outdoor auras and learned passives through the shared aura lifecycle."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PassiveSpells
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Environment

  def reconcile(%Character{internal: %{taxi_flight: nil}} = character, now) do
    if Death.alive?(character) do
      character
      |> remove_invalid(now)
      |> restore_passives(now)
    else
      character
    end
  end

  def reconcile(character, _now), do: character

  defp remove_invalid(character, now) do
    ids =
      for %Holder{spell: spell} <- character.unit.auras || [],
          invalid?(character, spell),
          do: spell.id

    {character, events} = Aura.remove_spells(character, ids, now)
    Effects.enqueue(character, events)
  end

  defp invalid?(character, spell) do
    Spell.attribute?(spell, :only_outdoors) and
      (character.internal.outdoors? == false or
         (Environment.outdoor_passive?(spell) and
            Spell.shapeshift_cast_error(spell, character.unit.shapeshift_form) != :ok))
  end

  defp restore_passives(character, now) do
    {character, events} = PassiveSpells.restore(character, now, :outdoors)
    Effects.enqueue(character, events)
  end
end
