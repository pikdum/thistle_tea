defmodule ThistleTea.DB.Mangos.PoolCreatureTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "pool_creature_template" do
    field(:id, :integer)
    field(:pool_entry, :integer)
    field(:chance, :float)
    field(:description, :string)
    field(:flags, :integer)
  end
end
