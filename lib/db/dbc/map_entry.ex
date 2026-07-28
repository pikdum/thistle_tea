defmodule MapEntry do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "Map" do
    field(:area_table, :integer)
  end
end
