defmodule GameObject do
  use Ecto.Schema

  @primary_key {:guid, :integer, autogenerate: false}
  schema "gameobject" do
    field(:id, :integer, default: 0)
    field(:map, :integer, default: 0)
    field(:position_x, :float, default: 0.0)
    field(:position_y, :float, default: 0.0)
    field(:position_z, :float, default: 0.0)
    field(:orientation, :float, default: 0.0)
    field(:rotation0, :float, default: 0.0)
    field(:rotation1, :float, default: 0.0)
    field(:rotation2, :float, default: 0.0)
    field(:rotation3, :float, default: 0.0)
    field(:spawntimesecs, :integer, default: 0)
    field(:animprogress, :integer, default: 0)
    field(:state, :integer, default: 0)

    belongs_to(:game_object_template, GameObjectTemplate,
      foreign_key: :id,
      references: :entry,
      define_field: false
    )
  end
end
