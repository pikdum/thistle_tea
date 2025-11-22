defmodule ThistleTea.DB.Mangos.GameObject do
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.SpatialHash

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

    belongs_to(:game_object_template, Mangos.GameObjectTemplate,
      foreign_key: :id,
      references: :entry,
      define_field: false
    )

    has_one(:game_event_game_object, Mangos.GameEventGameObject,
      foreign_key: :guid,
      references: :guid
    )
  end

  def query_cell({map, _x, _y, _z} = cell, events \\ []) do
    {{x1, x2}, {y1, y2}, {z1, z2}} = SpatialHash.cell_bounds(cell)

    from(g in __MODULE__,
      where:
        g.map == ^map and g.position_x >= ^x1 and g.position_x < ^x2 and g.position_y >= ^y1 and
          g.position_y < ^y2 and g.position_z >= ^z1 and g.position_z < ^z2,
      join: gt in assoc(g, :game_object_template),
      left_join: ge in assoc(g, :game_event_game_object),
      where: ge.event in ^events or is_nil(ge.event),
      preload: [game_object_template: gt, game_event_game_object: ge],
      select: g
    )
  end
end
