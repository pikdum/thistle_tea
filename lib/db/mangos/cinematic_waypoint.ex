defmodule ThistleTea.DB.Mangos.CinematicWaypoint do
  use Ecto.Schema

  @primary_key false
  schema "cinematic_waypoints" do
    field(:cinematic, :integer)
    field(:timer, :integer)
    field(:position_x, :float)
    field(:position_y, :float)
    field(:position_z, :float)
    field(:comment, :string)
  end
end
