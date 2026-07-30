defmodule ThistleTea.DB.Mangos.TaxiPathTransition do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "taxi_path_transitions" do
    field(:in_path, :integer, primary_key: true)
    field(:out_path, :integer, primary_key: true)
    field(:in_node, :integer)
    field(:out_node, :integer)
    field(:build_min, :integer)
  end
end
