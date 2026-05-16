defmodule ThistleTea.DB.Mangos.CreatureTemplateSpells do
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "creature_template_spells" do
    field(:spell1, :integer)
    field(:spell2, :integer)
    field(:spell3, :integer)
    field(:spell4, :integer)
  end

  def spell_ids(%__MODULE__{spell1: s1, spell2: s2, spell3: s3, spell4: s4}) do
    Enum.filter([s1, s2, s3, s4], &(is_integer(&1) and &1 > 0))
  end

  def spell_ids(_), do: []
end
