defmodule ThistleTea.DB.Mangos.SpellArea do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_area" do
    field(:spell, :integer)
    field(:area, :integer)
    field(:quest_start, :integer)
    field(:quest_start_active, :integer)
    field(:quest_end, :integer)
    field(:aura_spell, :integer)
    field(:racemask, :integer)
    field(:gender, :integer)
    field(:autocast, :integer)
  end
end
