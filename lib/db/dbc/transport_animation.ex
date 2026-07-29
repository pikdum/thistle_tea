defmodule TransportAnimation do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "TransportAnimation" do
    field(:transport, :integer)
    field(:time_index, :integer)
    field(:location_x, :float)
    field(:location_y, :float)
    field(:location_z, :float)
    field(:sequence, :integer)
  end
end
