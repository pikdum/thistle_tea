defmodule TaxiPathNode do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "TaxiPathNode" do
    field(:taxi_path, :integer)
    field(:node_index, :integer)
    field(:map, :integer)
    field(:location_x, :float)
    field(:location_y, :float)
    field(:location_z, :float)
    field(:flags, :integer)
    field(:delay, :integer)
  end
end
