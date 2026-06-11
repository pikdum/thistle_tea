defmodule SkillLineAbility do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SkillLineAbility" do
    field(:skill_line, :integer)
    field(:spell, :integer)
    field(:race_mask, :integer)
    field(:class_mask, :integer)
    # column names in dbc.sqlite are shifted one left of the real 1.12 DBC
    # layout, so the forward-rank spell id lands in the acquire_method column
    field(:superseded_by, :integer, source: :acquire_method)
  end
end
