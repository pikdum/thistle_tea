defmodule ThistleTea.DB.Mangos.ScriptWaypoint do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "script_waypoint" do
    field(:entry, :integer)
    field(:point, :integer, source: :pointid)
    field(:position_x, :float, source: :location_x, default: 0.0)
    field(:position_y, :float, source: :location_y, default: 0.0)
    field(:position_z, :float, source: :location_z, default: 0.0)
    field(:waittime, :integer, default: 0)
    field(:point_comment, :string)
    field(:orientation, :float, virtual: true, default: 100.0)
    field(:script_id, :integer, virtual: true, default: 0)
  end
end
