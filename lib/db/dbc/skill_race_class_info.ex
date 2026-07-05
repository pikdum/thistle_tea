defmodule SkillRaceClassInfo do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SkillRaceClassInfo" do
    field(:skill_line, :integer)
    field(:race_mask, :integer)
    field(:class_mask, :integer)
    field(:flags, :integer)
    field(:skill_tier, :integer)
  end
end
