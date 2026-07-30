defmodule TaxiPath do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "TaxiPath" do
    field(:source_taxi_node, :integer)
    field(:destination_taxi_node, :integer)
    field(:cost, :integer)
  end
end
