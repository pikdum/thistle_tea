defmodule ThistleTea.DB.Mangos.PoolTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "pool_template" do
    field(:max_limit, :integer)
    field(:description, :string)
    field(:flags, :integer)
    field(:instance, :integer)
    field(:patch_min, :integer)
    field(:patch_max, :integer)
  end
end
