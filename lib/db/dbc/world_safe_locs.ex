defmodule WorldSafeLocs do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "WorldSafeLocs" do
    field(:map, :integer)
    field(:location_x, :float)
    field(:location_y, :float)
    field(:location_z, :float)
    field(:area_name_en_gb, :string)
  end
end
