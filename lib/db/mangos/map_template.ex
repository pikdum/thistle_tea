defmodule ThistleTea.DB.Mangos.MapTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "map_template" do
    field(:entry, :integer)
    field(:patch, :integer)
    field(:parent, :integer)
    field(:map_type, :integer)
    field(:linked_zone, :integer)
    field(:player_limit, :integer)
    field(:reset_delay, :integer)
    field(:ghost_entrance_map, :integer)
    field(:ghost_entrance_x, :float)
    field(:ghost_entrance_y, :float)
    field(:map_name, :string)
    field(:script_name, :string)
  end
end
