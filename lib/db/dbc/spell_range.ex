defmodule SpellRange do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SpellRange" do
    field(:range_min, :float)
    field(:range_max, :float)
    field(:flags, :integer)
  end
end
