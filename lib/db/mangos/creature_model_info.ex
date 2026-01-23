defmodule ThistleTea.DB.Mangos.CreatureModelInfo do
  use Ecto.Schema

  @primary_key {:modelid, :integer, autogenerate: false}
  schema "creature_model_info" do
    field(:bounding_radius, :float, default: 0.0)
    field(:combat_reach, :float, default: 0.0)
    field(:gender, :integer, default: 2)
    field(:modelid_other_gender, :integer, default: 0)
    field(:modelid_other_team, :integer, default: 0)
  end
end
