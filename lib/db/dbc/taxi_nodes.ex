defmodule TaxiNodes do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "TaxiNodes" do
    field(:map, :integer)
    field(:location_x, :float)
    field(:location_y, :float)
    field(:location_z, :float)
    field(:name_en_gb, :string)
    field(:mount_creature_display_info_0, :integer)
    field(:mount_creature_display_info_1, :integer)
  end
end
