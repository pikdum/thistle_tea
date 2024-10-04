defmodule SpellCastTimes do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SpellCastTimes" do
    field(:base, :integer)
    field(:per_level_increase, :integer)
    field(:minimum, :integer)
  end
end
