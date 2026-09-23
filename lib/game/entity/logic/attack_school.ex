defmodule ThistleTea.Game.Entity.Logic.AttackSchool do
  @moduledoc "Melee damage schools from creature templates and attack snapshots."

  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Spell

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  def melee(%{internal: %{creature: %Creature{damage_school: school}}}) when school in 0..6,
    do: Enum.at(@schools, school)

  def melee(_entity), do: :physical

  def from_mask(mask) when is_integer(mask) and mask > 0 do
    Enum.find(@schools, :physical, &(Bitwise.band(Spell.school_mask(&1), mask) != 0))
  end

  def from_mask(_mask), do: :physical
end
