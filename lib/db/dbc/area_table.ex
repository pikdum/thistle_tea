defmodule AreaTable do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "AreaTable" do
    field(:map, :integer)
    field(:parent_area_table, :integer)
    field(:area_bit, :integer)
    field(:flags, :integer)
    field(:exploration_level, :integer)
    field(:name, :string, source: :area_name_en_gb)
  end
end
