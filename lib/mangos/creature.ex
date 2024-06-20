defmodule Creature do
  use Ecto.Schema

  @primary_key {:guid, :integer, autogenerate: false}

  schema "creature" do
    field(:id, :integer, default: 0)
    field(:map, :integer, default: 0)
    field(:modelid, :integer, default: 0)
    field(:equipment_id, :integer, default: 0)
    field(:position_x, :float, default: 0.0)
    field(:position_y, :float, default: 0.0)
    field(:position_z, :float, default: 0.0)
    field(:orientation, :float, default: 0.0)
    field(:spawntimesecs, :integer, default: 120)
    field(:spawndist, :float, default: 5.0)
    field(:currentwaypoint, :integer, default: 0)
    field(:curhealth, :integer, default: 1)
    field(:curmana, :integer, default: 0)
    field(:death_state, :integer, source: :DeathState, default: 0)
    field(:movement_type, :integer, source: :MovementType, default: 0)

    belongs_to(:creature_template, CreatureTemplate,
      foreign_key: :id,
      references: :entry,
      define_field: false
    )

    has_many(:creature_movement, CreatureMovement, foreign_key: :id, references: :guid)
  end
end
