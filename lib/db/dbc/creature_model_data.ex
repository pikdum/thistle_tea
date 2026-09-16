defmodule CreatureModelData do
  @moduledoc """
  Model scale and collision height. The pinned Vanilla DBC converter names
  column 15 `mount_height`; Vanilla's CreatureModelData uses it for collision
  height (column 14 is collision width).
  """
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "CreatureModelData" do
    field(:model_scale, :float)
    field(:collision_height, :float, source: :mount_height)
  end
end
