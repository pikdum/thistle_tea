defmodule ThistleTea.DB.Mangos.PetLevelStats do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "pet_levelstats" do
    field(:entry, :integer, primary_key: true)
    field(:level, :integer, primary_key: true)
    field(:health, :integer)
    field(:mana, :integer)
    field(:armor, :integer)
    field(:dmg_min, :float)
    field(:dmg_max, :float)
    field(:strength, :integer)
    field(:agility, :integer)
    field(:stamina, :integer)
    field(:intellect, :integer)
    field(:spirit, :integer)
  end
end
