defmodule CreatureDisplayInfo do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "CreatureDisplayInfo" do
    field(:model, :integer)
    field(:creature_model_scale, :float)
  end
end
