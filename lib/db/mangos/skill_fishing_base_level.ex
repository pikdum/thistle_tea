defmodule ThistleTea.DB.Mangos.SkillFishingBaseLevel do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}

  schema "skill_fishing_base_level" do
    field(:skill, :integer, default: 0)
  end
end
