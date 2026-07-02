defmodule ThistleTea.DB.Mangos.CreatureClassLevelStats do
  @moduledoc false
  use Ecto.Schema

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "creature_classlevelstats" do
    field(:class, :integer)
    field(:level, :integer)
    field(:melee_damage, :float)
    field(:ranged_damage, :float)
    field(:attack_power, :integer)
    field(:ranged_attack_power, :integer)
    field(:health, :integer)
    field(:base_health, :integer)
    field(:mana, :integer)
    field(:base_mana, :integer)
    field(:strength, :integer)
    field(:agility, :integer)
    field(:stamina, :integer)
    field(:intellect, :integer)
    field(:spirit, :integer)
    field(:armor, :integer)
  end

  def get(class, level) do
    Mangos.Repo.get_by(__MODULE__, class: class, level: level)
  end
end
