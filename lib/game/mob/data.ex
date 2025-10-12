defmodule ThistleTea.Game.Mob.Data do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.FieldStruct

  @creature_guid_offset 0xF1300000
  @update_flag_living 0x20

  defstruct object: %FieldStruct.Object{},
            unit: %FieldStruct.Unit{},
            movement_block: %FieldStruct.MovementBlock{},
            internal: %FieldStruct.Internal{}

  def build(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = ct} = c) do
    %__MODULE__{
      object: %FieldStruct.Object{
        guid: c.guid + @creature_guid_offset,
        entry: c.id,
        scale_x: scale(c)
      },
      unit: %FieldStruct.Unit{
        health: c.curhealth,
        power1: c.curmana,
        max_health: c.curhealth,
        max_power1: c.curmana,
        level: level(c),
        faction_template: ct.faction_alliance,
        flags: ct.unit_flags,
        display_id: c.modelid,
        native_display_id: c.modelid,
        npc_flags: ct.npc_flags
      },
      movement_block: %FieldStruct.MovementBlock{
        update_flag: @update_flag_living,
        position: {
          c.position_x,
          c.position_y,
          c.position_z,
          c.orientation
        },
        movement_flags: 0,
        # TODO: figure out how to generate these
        timestamp: 0,
        fall_time: 0.0,
        # from creature_template
        walk_speed: ct.speed_walk,
        run_speed: ct.speed_run,
        run_back_speed: ct.speed_run,
        swim_speed: ct.speed_run,
        swim_back_speed: ct.speed_run,
        turn_rate: 3.1415
      },
      internal: %FieldStruct.Internal{
        map: c.map,
        name: ct.name,
        spawn_distance: c.spawndist,
        movement_type: c.movement_type
      }
    }
  end

  defp scale(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{scale: scale}}) do
    if scale > 0, do: scale, else: 1.0
  end

  defp level(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{min_level: min_level, max_level: max_level}}) do
    Enum.random(min_level..max_level)
  end
end
