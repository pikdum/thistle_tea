defmodule ThistleTea.DB.Mangos.PetCreateInfoSpell do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "petcreateinfo_spell" do
    field(:spell1, :integer)
    field(:spell2, :integer)
    field(:spell3, :integer)
    field(:spell4, :integer)
    field(:patch_min, :integer)
    field(:patch_max, :integer)
  end

  def spell_ids(%__MODULE__{} = row) do
    [row.spell1, row.spell2, row.spell3, row.spell4]
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
  end
end
