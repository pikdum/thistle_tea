defmodule ThistleTea.Game.Spell.Environment do
  @moduledoc "Pure indoor and outdoor spell requirements over resolved terrain state."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Spell

  def restricted?(%Spell{} = spell),
    do: Spell.attribute?(spell, :only_indoors) or Spell.attribute?(spell, :only_outdoors)

  def validate(%Character{}, %Spell{} = spell, outdoors), do: validate(spell, outdoors)
  def validate(_entity, _spell, _outdoors), do: :ok

  def validate(%Spell{} = spell, false) do
    if Spell.attribute?(spell, :only_outdoors), do: {:error, :only_outdoors}, else: :ok
  end

  def validate(%Spell{} = spell, true) do
    if Spell.attribute?(spell, :only_indoors), do: {:error, :only_indoors}, else: :ok
  end

  def validate(%Spell{}, nil), do: :ok

  def outdoor_passive?(%Spell{} = spell),
    do: Spell.attribute?(spell, :only_outdoors) and Spell.attribute?(spell, :passive)
end
