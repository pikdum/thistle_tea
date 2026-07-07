defmodule ThistleTea.DB.Mangos.SpellThreat do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_threat" do
    field(:entry, :integer)
    field(:threat, :float)
    field(:multiplier, :float)
    field(:inverse_effect_mask, :integer)
    field(:build_min, :integer)
    field(:build_max, :integer)
  end
end
