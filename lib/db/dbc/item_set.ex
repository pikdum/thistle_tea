defmodule ItemSet do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "ItemSet" do
    field(:name_en_gb, :string)
    field(:required_skill, :integer)
    field(:required_skill_rank, :integer)

    for index <- 0..7 do
      field(:"set_spell_#{index}", :integer)
      field(:"set_threshold_#{index}", :integer)
    end
  end
end
