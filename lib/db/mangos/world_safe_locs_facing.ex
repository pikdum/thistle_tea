defmodule ThistleTea.DB.Mangos.WorldSafeLocsFacing do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "world_safe_locs_facing" do
    field(:orientation, :float)
  end
end
