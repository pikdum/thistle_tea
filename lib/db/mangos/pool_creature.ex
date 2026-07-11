defmodule ThistleTea.DB.Mangos.PoolCreature do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "pool_creature" do
    field(:guid, :integer)
    field(:pool_entry, :integer)
    field(:chance, :float)
    field(:description, :string)
    field(:flags, :integer)
  end
end
