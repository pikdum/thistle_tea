defmodule SkillLineAbility do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SkillLineAbility" do
    field(:skill_line, :integer)
    field(:spell, :integer)
    field(:race_mask, :integer)
    field(:class_mask, :integer)
    field(:min_skill_line_rank, :integer)
    field(:superseded_by, :integer)
  end
end
