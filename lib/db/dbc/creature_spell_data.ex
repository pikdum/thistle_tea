defmodule CreatureSpellData do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "CreatureSpellData" do
    field(:spell_0, :integer)
    field(:spell_1, :integer)
    field(:spell_2, :integer)
    field(:spell_3, :integer)
  end

  def spell_ids(%__MODULE__{} = row) do
    [row.spell_0, row.spell_1, row.spell_2, row.spell_3]
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
  end
end
