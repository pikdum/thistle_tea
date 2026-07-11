defmodule ThistleTea.DB.Mangos.PoolGameObject do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "pool_gameobject" do
    field(:guid, :integer)
    field(:pool_entry, :integer)
    field(:chance, :float)
    field(:description, :string)
    field(:flags, :integer)
  end
end
