defmodule ThistleTea.DB.Mangos.AreaTriggerTemplate do
  use Ecto.Schema

  @primary_key false
  schema "areatrigger_template" do
    field(:id, :integer)
    field(:build, :integer)
    field(:name, :string)
    field(:map_id, :integer)
    field(:x, :float)
    field(:y, :float)
    field(:z, :float)
    field(:radius, :float)
    field(:box_x, :float)
    field(:box_y, :float)
    field(:box_z, :float)
    field(:box_orientation, :float)
  end
end
