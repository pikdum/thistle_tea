defmodule ThistleTea.DB.Mangos.GameTele do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "game_tele" do
    field(:position_x, :float)
    field(:position_y, :float)
    field(:position_z, :float)
    field(:orientation, :float)
    field(:map, :integer)
    field(:name, :string)
  end
end
