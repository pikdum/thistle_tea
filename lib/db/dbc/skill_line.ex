defmodule SkillLine do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SkillLine" do
    field(:category, :integer)
  end
end
