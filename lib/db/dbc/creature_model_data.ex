defmodule CreatureModelData do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "CreatureModelData" do
    field(:model_scale, :float)
  end
end
