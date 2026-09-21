defmodule ThistleTea.DB.Mangos.GameObjectDisplayInfoAddon do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:display_id, :integer, autogenerate: false}
  schema "gameobject_display_info_addon" do
    field(:min_x, :float, default: 0.0)
    field(:min_y, :float, default: 0.0)
    field(:min_z, :float, default: 0.0)
    field(:max_x, :float, default: 0.0)
    field(:max_y, :float, default: 0.0)
    field(:max_z, :float, default: 0.0)
  end
end
