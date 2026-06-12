defmodule ThistleTea.Game.Entity.Data.Mob do
  @moduledoc """
  Mob entity built from Mangos `creature` spawn rows and their templates,
  including respawn reset and the metadata used for visibility queries.
  """
  import Bitwise, only: [|||: 2, <<<: 2, &&&: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Guid

  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40
  @default_respawn_delay_ms 120_000

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

    model_info = Map.get(c, :creature_model_info)
    effective_scale = effective_scale(ct, Map.get(c, :display_scale))
    {virtual_item_slot_display, virtual_item_info} = virtual_items(Map.get(c, :equip_items))

    unit = %Unit{
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
      bounding_radius: mob_bounding_radius(model_info, effective_scale),
      combat_reach: mob_combat_reach(model_info, effective_scale),
      display_id: c.modelid,
      native_display_id: c.modelid,
      min_damage: ct.min_melee_dmg,
      max_damage: ct.max_melee_dmg,
      base_attack_time: ct.melee_base_attack_time,
      attack_power: ct.melee_attack_power,
      virtual_item_slot_display: virtual_item_slot_display,
      virtual_item_info: virtual_item_info,
      auras: []
    }

    movement_block = %MovementBlock{
      update_flag: @update_flag_all ||| @update_flag_living ||| @update_flag_has_position,
      position: {
        c.position_x,
        c.position_y,
        c.position_z,
        c.orientation
      },
      movement_flags: 0,
      # TODO: figure out how to generate these
      timestamp: 0,
      fall_time: 0,
      # from creature_template
      walk_speed: ct.speed_walk * 2.5,
      run_speed: ct.speed_run * 7.0,
      run_back_speed: ct.speed_run * 4.5,
      swim_speed: ct.speed_run * 4.722222,
      swim_back_speed: ct.speed_run * 2.5,
      base_walk_speed: ct.speed_walk * 2.5,
      base_run_speed: ct.speed_run * 7.0,
      base_run_back_speed: ct.speed_run * 4.5,
      base_swim_speed: ct.speed_run * 4.722222,
      base_swim_back_speed: ct.speed_run * 2.5,
      turn_rate: 3.1415
    }

    %__MODULE__{
      object: %Object{
        guid: Guid.from_low_guid(:mob, c.id, c.guid),
        entry: c.id,
        scale_x: effective_scale
      },
      unit: unit,
      movement_block: movement_block,
      internal: %Internal{
        map: c.map,
        name: ct.name,
        spawn_distance: c.spawndist,
        movement_type: c.movement_type,
        experience_multiplier: ct.experience_multiplier,
        extra_flags: ct.extra_flags,
        creature_type_flags: ct.creature_type_flags,
        regenerate_stats: ct.regenerate_stats,
        rank: ct.rank,
        respawn_delay_ms: respawn_delay_ms(c.spawntimesecs),
        loot_id: ct.loot_id,
        min_loot_gold: ct.min_loot_gold,
        max_loot_gold: ct.max_loot_gold,
        spawn_unit: unit,
        spawn_movement_block: movement_block,
        initial_position: {c.position_x, c.position_y, c.position_z},
        waypoint_route: WaypointRoute.build(c),
        event: event,
        in_combat: false,
        running: false,
        spellbook: Map.get(c, :spellbook, %{})
      }
    }
  end

  @npc_flag_spirit_service 0x60
  @creature_type_flag_ghost_visible 0x02

  def visibility_metadata(%__MODULE__{unit: %Unit{} = unit, internal: %Internal{} = internal}) do
    %{
      spirit_service?: ((unit.npc_flags || 0) &&& @npc_flag_spirit_service) != 0,
      ghost_visible?: ((internal.creature_type_flags || 0) &&& @creature_type_flag_ghost_visible) != 0
    }
  end

  def respawn(%__MODULE__{internal: %Internal{} = internal} = mob) do
    unit = respawn_unit(internal, mob.unit)
    movement_block = respawn_movement_block(internal, mob.movement_block)

    internal =
      %{
        internal
        | in_combat: false,
          last_hostile_time: nil,
          running: false,
          movement_start_time: nil,
          movement_start_position: nil,
          behavior_tree: nil,
          blackboard: nil,
          respawn_ref: nil,
          broadcast_update?: false,
          loot: nil
      }
      |> Map.merge(%{tapped_by: nil, assigned_looter: nil, loot_master: nil, loot_rolls: %{}, respawn_deferrals: 0})

    %{mob | unit: unit, movement_block: movement_block, internal: internal}
  end

  defp effective_scale(%Mangos.CreatureTemplate{scale: scale}, _display_scale) when is_number(scale) and scale > 0,
    do: scale

  defp effective_scale(_template, display_scale) when is_number(display_scale) and display_scale > 0, do: display_scale

  defp effective_scale(_template, _display_scale), do: 1.0

  defp level(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{min_level: min_level, max_level: max_level}}) do
    Enum.random(min_level..max_level)
  end

  defp respawn_delay_ms(seconds) when is_integer(seconds) and seconds >= 0 do
    seconds * 1_000
  end

  defp respawn_delay_ms(_seconds), do: @default_respawn_delay_ms

  defp respawn_unit(%Internal{spawn_unit: %Unit{} = unit}, _current_unit), do: unit

  defp respawn_unit(%Internal{}, %Unit{} = unit) do
    %{
      unit
      | health: unit.max_health,
        power1: unit.max_power1,
        power2: unit.max_power2,
        power3: unit.max_power3,
        power4: unit.max_power4,
        power5: unit.max_power5,
        target: 0
    }
  end

  defp respawn_movement_block(
         %Internal{spawn_movement_block: %MovementBlock{} = movement_block},
         _current_movement_block
       ) do
    movement_block
  end

  defp respawn_movement_block(%Internal{initial_position: {x, y, z}}, %MovementBlock{} = movement_block) do
    %{movement_block | position: {x, y, z, 0.0}, movement_flags: 0}
  end

  defp respawn_movement_block(%Internal{}, %MovementBlock{} = movement_block) do
    %{movement_block | movement_flags: 0}
  end

  defp mob_bounding_radius(model_info, scale) do
    normalize_model_value(model_info, :bounding_radius, Unit.default_bounding_radius()) * scale
  end

  defp mob_combat_reach(model_info, scale) do
    normalize_model_value(model_info, :combat_reach, Unit.default_combat_reach()) * scale
  end

  defp virtual_items([_, _, _] = items) do
    if Enum.all?(items, &is_nil/1) do
      {nil, nil}
    else
      {pack_virtual_item_slot_display(items), pack_virtual_item_info(items)}
    end
  end

  defp virtual_items(_items), do: {nil, nil}

  defp pack_virtual_item_slot_display([a, b, c]) do
    item_display_id(a) ||| item_display_id(b) <<< 32 ||| item_display_id(c) <<< 64
  end

  defp pack_virtual_item_info([a, b, c]) do
    virtual_item_info_for(a) <> virtual_item_info_for(b) <> virtual_item_info_for(c)
  end

  defp virtual_item_info_for(%Mangos.CreatureItemTemplate{
         class: class,
         subclass: subclass,
         material: material,
         inventory_type: inventory_type,
         sheath_type: sheath_type
       }) do
    <<class, subclass, material, inventory_type, sheath_type, 0, 0, 0>>
  end

  defp virtual_item_info_for(nil), do: <<0::64>>

  defp item_display_id(%Mangos.CreatureItemTemplate{display_id: id}), do: id
  defp item_display_id(nil), do: 0

  defp normalize_model_value(%Mangos.CreatureModelInfo{} = model_info, key, default) do
    case Map.get(model_info, key) do
      value when is_number(value) and value > 0 -> value
      _ -> default
    end
  end

  defp normalize_model_value(_model_info, _key, default), do: default
end
