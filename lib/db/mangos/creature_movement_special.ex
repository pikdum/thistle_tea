defmodule ThistleTea.DB.Mangos.CreatureMovementSpecial do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "creature_movement_special" do
    field(:id, :integer)
    field(:point, :integer)
    field(:position_x, :float, default: 0.0)
    field(:position_y, :float, default: 0.0)
    field(:position_z, :float, default: 0.0)
    field(:orientation, :float, default: 0.0)
    field(:waittime, :integer, default: 0)
    field(:wander_distance, :float, default: 0.0)
    field(:script_id, :integer, default: 0)
    field(:path_id, :integer, default: 0)
  end
end
