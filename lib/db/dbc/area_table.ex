defmodule AreaTable do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "AreaTable" do
    field(:map, :integer)
    field(:flags, :integer)
  end
end
