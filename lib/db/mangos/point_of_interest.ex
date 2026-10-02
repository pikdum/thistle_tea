defmodule ThistleTea.DB.Mangos.PointOfInterest do
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "points_of_interest" do
    field(:x, :float, default: 0.0)
    field(:y, :float, default: 0.0)
    field(:icon, :integer, default: 0)
    field(:flags, :integer, default: 0)
    field(:data, :integer, default: 0)
    field(:icon_name, :string)
  end
end
