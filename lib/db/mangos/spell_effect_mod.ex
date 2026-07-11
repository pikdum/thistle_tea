defmodule ThistleTea.DB.Mangos.SpellEffectMod do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, source: :Id, autogenerate: false}
  schema "spell_effect_mod" do
    field(:effect_base_points, :integer, source: :EffectBasePoints)
  end
end
