defmodule SpellDuration do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SpellDuration" do
    field(:duration, :integer)
    field(:duration_per_level, :integer)
    field(:max_duration, :integer)
  end
end
