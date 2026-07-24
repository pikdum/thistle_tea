defmodule ThistleTea.DB.Mangos.SpellPetAura do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_pet_auras" do
    field(:spell, :integer)
    field(:pet, :integer)
    field(:aura, :integer)
  end
end
