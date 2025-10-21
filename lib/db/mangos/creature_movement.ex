defmodule ThistleTea.DB.Mangos.CreatureMovement do
  use Ecto.Schema

  import Ecto.Query

  @primary_key {:id, :integer, autogenerate: false}
  schema "creature_movement" do
    field(:point, :integer)
    field(:position_x, :float, default: 0.0)
    field(:position_y, :float, default: 0.0)
    field(:position_z, :float, default: 0.0)
    field(:waittime, :integer, default: 0)
    field(:script_id, :integer, default: 0)
    field(:textid1, :integer, default: 0)
    field(:textid2, :integer, default: 0)
    field(:textid3, :integer, default: 0)
    field(:textid4, :integer, default: 0)
    field(:textid5, :integer, default: 0)
    field(:emote, :integer, default: 0)
    field(:spell, :integer, default: 0)
    field(:orientation, :float, default: 0.0)
    field(:model1, :integer, default: 0)
    field(:model2, :integer, default: 0)

    # belongs_to(:creature, Creature, foreign_key: :id, references: :guid, define_field: false)
  end

  def query(creature_guid) do
    from(cm in __MODULE__,
      where: cm.id == ^creature_guid,
      order_by: cm.point
    )
  end

  def first_point(creature_movement) do
    creature_movement
    |> Enum.map(& &1.point)
    |> Enum.min()
  end

  def closest_point(creature_movement, {x, y, z}) do
    creature_movement
    |> Enum.min_by(fn %__MODULE__{} = cm ->
      SpatialHash.distance({cm.position_x, cm.position_y, cm.position_z}, {x, y, z})
    end)
    |> Map.get(:point)
  end
end
