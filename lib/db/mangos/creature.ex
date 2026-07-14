defmodule ThistleTea.DB.Mangos.Creature do
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.SpatialHash

  @primary_key {:guid, :integer, autogenerate: false}

  schema "creature" do
    field(:id, :integer, default: 0)
    field(:id2, :integer, default: 0)
    field(:id3, :integer, default: 0)
    field(:id4, :integer, default: 0)
    field(:id5, :integer, default: 0)
    field(:map, :integer, default: 0)
    field(:position_x, :float, default: 0.0)
    field(:position_y, :float, default: 0.0)
    field(:position_z, :float, default: 0.0)
    field(:orientation, :float, default: 0.0)
    field(:spawntimesecsmin, :integer, default: 120)
    field(:spawntimesecsmax, :integer, default: 120)
    field(:wander_distance, :float, default: 5.0)
    field(:health_percent, :float, default: 100.0)
    field(:mana_percent, :float, default: 100.0)
    field(:movement_type, :integer, default: 0)
    field(:modelid, :integer, virtual: true, default: 0)
    field(:spawntimesecs, :integer, virtual: true)
    field(:spawndist, :float, virtual: true)
    field(:curhealth, :integer, virtual: true)
    field(:curmana, :integer, virtual: true)
    field(:selected_level, :integer, virtual: true)
    field(:display_scale, :float, virtual: true)
    field(:creature_display_info_addon, :any, virtual: true)
    field(:creature_class_level_stats, :any, virtual: true)
    field(:equip_items, :any, virtual: true, default: [nil, nil, nil])
    field(:movement_scripts, :map, virtual: true, default: %{})
    field(:ai_events, :any, virtual: true, default: [])
    field(:spellbook, :map, virtual: true, default: %{})
    field(:spell_list, :any, virtual: true, default: [])
    field(:addon_auras, :any, virtual: true, default: [])

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

  def query_cell({map, _x, _y} = cell, events \\ []) do
    {{x1, x2}, {y1, y2}} = SpatialHash.cell_bounds(cell)

    from(c in __MODULE__,
      where:
        c.map == ^map and c.position_x >= ^x1 and c.position_x < ^x2 and c.position_y >= ^y1 and
          c.position_y < ^y2,
      left_join: ce in assoc(c, :game_event_creature),
      where: ce.event in ^events or is_nil(ce.event),
      preload: [game_event_creature: ce],
      select: c
    )
  end

  def query_guids(guids, events \\ []) when is_list(guids) do
    from(c in __MODULE__,
      where: c.guid in ^guids,
      left_join: ce in assoc(c, :game_event_creature),
      where: ce.event in ^events or is_nil(ce.event),
      preload: [game_event_creature: ce],
      select: c
    )
  end
end
