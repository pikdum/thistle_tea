defmodule ThistleTea.DB.Mangos.TaxiNode do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "taxi_nodes" do
    field(:id, :integer, primary_key: true)
    field(:build, :integer, primary_key: true)
    field(:map_id, :integer)
    field(:x, :float)
    field(:y, :float)
    field(:z, :float)
    field(:name, :string)
    field(:mount_creature_id1, :integer)
    field(:mount_creature_id2, :integer)
  end
end
