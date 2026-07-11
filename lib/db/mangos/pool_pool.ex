defmodule ThistleTea.DB.Mangos.PoolPool do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "pool_pool" do
    field(:pool_id, :integer)
    field(:mother_pool, :integer)
    field(:chance, :float)
    field(:description, :string)
    field(:flags, :integer)
  end
end
