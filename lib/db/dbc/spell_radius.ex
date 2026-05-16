defmodule SpellRadius do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SpellRadius" do
    field(:radius, :float)
    field(:radius_per_level, :float)
    field(:radius_max, :float)
  end
end
