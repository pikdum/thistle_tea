defmodule ThistleTea.Game.Entity.Logic.Honor.Protection do
  @moduledoc """
  Grants travel-arrival Honorless Target protection in enforced PvP territory.
  Duration and interrupt rules come from the loaded spell and shared aura lifecycle.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @spell_id 2479

  def spell_id, do: @spell_id

  def eligible?(%Character{} = character) do
    character.internal.pvp.enforced? and Death.alive?(character) and is_nil(character.internal.taxi_flight)
  end

  def apply(%Character{} = character, %Spell{id: @spell_id} = spell, now) do
    if eligible?(character) do
      {character, events} = Aura.apply_spell(character, character.object.guid, character.unit.level, spell, now)
      Effects.enqueue(character, events)
    else
      character
    end
  end

  def apply(%Character{} = character, _spell, _now), do: character
end
