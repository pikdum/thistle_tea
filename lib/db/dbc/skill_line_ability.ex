defmodule SkillLineAbility do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SkillLineAbility" do
    field(:skill_line, :integer)
    field(:spell, :integer)
    field(:race_mask, :integer)
    field(:class_mask, :integer)
    field(:min_skill_line_rank, :integer)
    field(:trivial_skill_line_rank_low, :integer)
    field(:trivial_skill_line_rank_high, :integer)
    field(:superseded_by, :integer)
    field(:acquire_method, :integer)
  end
end
