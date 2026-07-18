defmodule ThistleTea.DB.Mangos.SpellTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_template" do
    field(:entry, :integer)
    field(:build, :integer)
    field(:script_name, :string)
    field(:effect_bonus_coefficient_0, :float, source: :effectBonusCoefficient1)
    field(:effect_bonus_coefficient_1, :float, source: :effectBonusCoefficient2)
    field(:effect_bonus_coefficient_2, :float, source: :effectBonusCoefficient3)
  end
end
