defmodule ThistleTea.DB.Mangos.Creature do
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.SpatialHash

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

    belongs_to(:creature_template, Mangos.CreatureTemplate,
      foreign_key: :id,
      references: :entry,
      define_field: false
    )

    has_many(:creature_movement, Mangos.CreatureMovement, foreign_key: :id, references: :guid)

    has_one(:game_event_creature, Mangos.GameEventCreature,
      foreign_key: :guid,
      references: :guid
    )
  end

  def query_cell({map, _x, _y, _z} = cell, events \\ []) do
    {{x1, x2}, {y1, y2}, {z1, z2}} = SpatialHash.cell_bounds(cell)

    from(c in __MODULE__,
      where:
        c.map == ^map and c.position_x >= ^x1 and c.position_x < ^x2 and c.position_y >= ^y1 and
          c.position_y < ^y2 and c.position_z >= ^z1 and c.position_z < ^z2,
      join: ct in assoc(c, :creature_template),
      left_join: ce in assoc(c, :game_event_creature),
      where: ce.event in ^events or is_nil(ce.event),
      where: c.modelid != 0,
      preload: [creature_template: ct],
      select: c
    )
  end
end
