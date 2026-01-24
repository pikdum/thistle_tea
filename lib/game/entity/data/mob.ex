defmodule ThistleTea.Game.Entity.Data.Mob do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Guid

  @update_flag_living 0x20

  defstruct object: %Object{},
            unit: %Unit{},
            movement_block: %MovementBlock{},
            internal: %Internal{}

  def build(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = ct} = c) do
    event =
      case c.game_event_creature do
        %Mangos.GameEventCreature{event: event} -> event
        _ -> nil
      end

    model_info = creature_model_info(c)

    %__MODULE__{
      object: %Object{
        guid: Guid.from_low_guid(:mob, c.id, c.guid),
        entry: c.id,
        scale_x: scale(c)
      },
      unit: %Unit{
        health: c.curhealth,
        power1: c.curmana,
        max_health: c.curhealth,
        max_power1: c.curmana,
        level: level(c),
        faction_template: ct.faction_alliance,
        flags: ct.unit_flags,
        npc_flags: ct.npc_flags,
        dynamic_flags: ct.dynamic_flags,
        misc_flags: ct.extra_flags,
        bounding_radius: mob_bounding_radius(ct, model_info),
        combat_reach: mob_combat_reach(ct, model_info),
        display_id: c.modelid,
        native_display_id: c.modelid
      },
      movement_block: %MovementBlock{
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
      internal: %Internal{
        map: c.map,
        name: ct.name,
        spawn_distance: c.spawndist,
        movement_type: c.movement_type,
        initial_position: {c.position_x, c.position_y, c.position_z},
        waypoint_route: WaypointRoute.build(c),
        event: event,
        in_combat: false,
        running: false
      }
    }
  end

  defp scale(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{scale: scale}}) do
    if scale > 0, do: scale, else: 1.0
  end

  defp level(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{min_level: min_level, max_level: max_level}}) do
    Enum.random(min_level..max_level)
  end

  defp mob_bounding_radius(%Mangos.CreatureTemplate{} = template, model_info) do
    normalize_model_value(model_info, :bounding_radius, Unit.default_bounding_radius()) * scale_factor(template)
  end

  defp mob_combat_reach(%Mangos.CreatureTemplate{} = template, model_info) do
    normalize_model_value(model_info, :combat_reach, Unit.default_combat_reach()) * scale_factor(template)
  end

  defp scale_factor(%Mangos.CreatureTemplate{scale: scale}) when is_number(scale) and scale > 0 do
    scale
  end

  defp scale_factor(_template), do: 1.0

  defp creature_model_info(%Mangos.Creature{modelid: modelid}) when is_integer(modelid) and modelid > 0 do
    Mangos.Repo.get(Mangos.CreatureModelInfo, modelid)
  end

  defp creature_model_info(_creature), do: nil

  defp normalize_model_value(%Mangos.CreatureModelInfo{} = model_info, key, default) do
    case Map.get(model_info, key) do
      value when is_number(value) and value > 0 -> value
      _ -> default
    end
  end

  defp normalize_model_value(_model_info, _key, default), do: default
end
