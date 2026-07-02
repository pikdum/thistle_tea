defmodule ThistleTea.Game.Entity.Data.Mob do
  @moduledoc """
  Mob entity built from Mangos `creature` spawn rows and their templates,
  including respawn reset and the metadata used for visibility queries.
  """
  import Bitwise, only: [|||: 2, <<<: 2, &&&: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Time

  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40
  @default_respawn_delay_ms 120_000
  @static_flag_no_automatic_regen 0x00000400
  @static_flag_visible_to_ghosts 0x00200000
  @creature_type_flag_ghost_visible 0x02

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
    level = level(c)
    stats = Map.get(c, :creature_class_level_stats)
    {health, max_health} = health_values(c, ct, stats)
    {mana, max_mana} = mana_values(c, ct, stats)
    {min_damage, max_damage} = melee_damage_values(ct, stats)

    unit = %Unit{
      health: health,
      power1: mana,
      max_health: max_health,
      max_power1: max_mana,
      level: level,
      faction_template: ct.faction_alliance,
      flags: unit_flags(ct),
      npc_flags: ct.npc_flags,
      dynamic_flags: ct.dynamic_flags || 0,
      misc_flags: ct.extra_flags,
      bounding_radius: mob_bounding_radius(model_info, effective_scale),
      combat_reach: mob_combat_reach(model_info, effective_scale),
      display_id: c.modelid,
      native_display_id: c.modelid,
      min_damage: min_damage,
      max_damage: max_damage,
      base_attack_time: ct.melee_base_attack_time,
      attack_power: stat_value(stats, :attack_power, ct.melee_attack_power),
      ranged_attack_power: stat_value(stats, :ranged_attack_power, ct.ranged_attack_power),
      min_ranged_damage: ranged_damage_min(ct, stats),
      max_ranged_damage: ranged_damage_max(ct, stats),
      strength: stat_value(stats, :strength, 0),
      agility: stat_value(stats, :agility, 0),
      stamina: stat_value(stats, :stamina, 0),
      intellect: stat_value(stats, :intellect, 0),
      spirit: stat_value(stats, :spirit, 0),
      normal_resistance: armor_value(ct, stats),
      holy_resistance: ct.resistance_holy,
      fire_resistance: ct.resistance_fire,
      nature_resistance: ct.resistance_nature,
      frost_resistance: ct.resistance_frost,
      shadow_resistance: ct.resistance_shadow,
      arcane_resistance: ct.resistance_arcane,
      base_health: stat_value(stats, :base_health, max_health),
      base_mana: stat_value(stats, :base_mana, max_mana),
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
        creature: %Creature{
          experience_multiplier: ct.experience_multiplier,
          extra_flags: ct.extra_flags,
          rank: ct.rank,
          type_flags: type_flags(ct),
          damage_multiplier: ct.damage_multiplier,
          regenerate_stats: regenerate_stats(ct),
          spells: Map.get(c, :spell_list, []),
          addon_auras: Map.get(c, :addon_auras, [])
        },
        spawn: %Spawn{
          unit: unit,
          movement_block: movement_block,
          position: {c.position_x, c.position_y, c.position_z},
          distance: spawn_distance(c),
          movement_type: c.movement_type,
          waypoint_route: WaypointRoute.build(c),
          respawn_delay_ms: respawn_delay_ms(c)
        },
        loot: %Loot{
          id: ct.loot_id,
          min_gold: ct.min_loot_gold,
          max_gold: ct.max_loot_gold
        },
        event: event,
        in_combat: false,
        running: false,
        spellbook: Map.get(c, :spellbook, %{})
      }
    }
    |> apply_addon_auras(Time.now())
  end

  def apply_addon_auras(%__MODULE__{internal: %Internal{creature: %Creature{addon_auras: [_ | _] = spells}}} = mob, now)
      when is_integer(now) do
    Enum.reduce(spells, mob, fn spell, acc ->
      {acc, _events} = AuraLogic.apply_spell(acc, acc.object.guid, acc.unit.level, spell, now)
      acc
    end)
  end

  def apply_addon_auras(%__MODULE__{} = mob, _now), do: mob

  @npc_flag_spirit_service 0x60

  def visibility_metadata(%__MODULE__{unit: %Unit{} = unit, internal: %Internal{creature: %Creature{} = creature}}) do
    %{
      spirit_service?: ((unit.npc_flags || 0) &&& @npc_flag_spirit_service) != 0,
      ghost_visible?: ((creature.type_flags || 0) &&& @creature_type_flag_ghost_visible) != 0
    }
  end

  def respawn(%__MODULE__{internal: %Internal{} = internal} = mob) do
    spawn_state = internal.spawn || %Spawn{}
    loot = internal.loot || %Loot{}

    unit = respawn_unit(spawn_state, mob.unit)
    movement_block = respawn_movement_block(spawn_state, mob.movement_block)

    internal = %{
      internal
      | in_combat: false,
        last_hostile_time: nil,
        casting: nil,
        rooted?: false,
        running: false,
        movement_start_time: nil,
        movement_start_position: nil,
        behavior_tree: nil,
        blackboard: nil,
        broadcast_update?: false,
        spawn: %{spawn_state | respawn_ref: nil, respawn_pending?: false},
        loot: %{loot | session: nil, tapped_by: nil, corpse_removed?: false, corpse_token: nil}
    }

    %{mob | unit: unit, movement_block: movement_block, internal: internal}
  end

  defp effective_scale(%Mangos.CreatureTemplate{scale: scale}, _display_scale) when is_number(scale) and scale > 0,
    do: scale

  defp effective_scale(_template, display_scale) when is_number(display_scale) and display_scale > 0, do: display_scale

  defp effective_scale(_template, _display_scale), do: 1.0

  defp level(%Mangos.Creature{} = creature) do
    case Map.get(creature, :selected_level) do
      level when is_integer(level) and level > 0 -> level
      _ -> random_template_level(creature)
    end
  end

  defp random_template_level(%Mangos.Creature{
         creature_template: %Mangos.CreatureTemplate{min_level: min_level, max_level: max_level}
       }) do
    Enum.random(min_level..max_level)
  end

  defp health_values(
         %Mangos.Creature{} = creature,
         %Mangos.CreatureTemplate{} = template,
         %Mangos.CreatureClassLevelStats{} = stats
       ) do
    max_health = stats.health |> multiplied(template.health_multiplier) |> max(1)
    {percent_value(max_health, creature.health_percent), max_health}
  end

  defp health_values(%Mangos.Creature{curhealth: health}, _template, _stats) when is_integer(health) and health > 0 do
    {health, health}
  end

  defp health_values(_creature, _template, _stats), do: {1, 1}

  defp mana_values(
         %Mangos.Creature{} = creature,
         %Mangos.CreatureTemplate{} = template,
         %Mangos.CreatureClassLevelStats{} = stats
       ) do
    max_mana = multiplied(stats.mana, template.mana_multiplier)
    {percent_value(max_mana, creature.mana_percent), max_mana}
  end

  defp mana_values(%Mangos.Creature{curmana: mana}, _template, _stats) when is_integer(mana) and mana > 0 do
    {mana, mana}
  end

  defp mana_values(_creature, _template, _stats), do: {0, 0}

  defp melee_damage_values(%Mangos.CreatureTemplate{} = template, %Mangos.CreatureClassLevelStats{} = stats) do
    average = stats.melee_damage * (template.damage_multiplier || 1.0)
    variance = average * (template.damage_variance || 0.14)
    {average - variance, average + variance}
  end

  defp melee_damage_values(%Mangos.CreatureTemplate{} = template, _stats),
    do: {template.min_melee_dmg, template.max_melee_dmg}

  defp ranged_damage_min(%Mangos.CreatureTemplate{} = template, %Mangos.CreatureClassLevelStats{} = stats) do
    average = stats.ranged_damage * (template.damage_multiplier || 1.0)
    average - average * (template.damage_variance || 0.14)
  end

  defp ranged_damage_min(%Mangos.CreatureTemplate{} = template, _stats), do: template.min_ranged_dmg

  defp ranged_damage_max(%Mangos.CreatureTemplate{} = template, %Mangos.CreatureClassLevelStats{} = stats) do
    average = stats.ranged_damage * (template.damage_multiplier || 1.0)
    average + average * (template.damage_variance || 0.14)
  end

  defp ranged_damage_max(%Mangos.CreatureTemplate{} = template, _stats), do: template.max_ranged_dmg

  defp stat_value(%Mangos.CreatureClassLevelStats{} = stats, key, _default), do: Map.get(stats, key) || 0
  defp stat_value(_stats, _key, default), do: default || 0

  defp armor_value(%Mangos.CreatureTemplate{} = template, %Mangos.CreatureClassLevelStats{} = stats) do
    multiplied(stats.armor, template.armor_multiplier)
  end

  defp armor_value(%Mangos.CreatureTemplate{} = template, _stats), do: template.armor || 0

  defp multiplied(value, multiplier) when is_number(value) and is_number(multiplier), do: round(value * multiplier)
  defp multiplied(value, _multiplier) when is_number(value), do: round(value)
  defp multiplied(_value, _multiplier), do: 0

  defp percent_value(value, percent) when is_integer(value) and value > 0 and is_number(percent) and percent < 100 do
    value
    |> Kernel.*(percent / 100.0)
    |> round()
    |> max(1)
  end

  defp percent_value(value, _percent), do: value

  defp unit_flags(%Mangos.CreatureTemplate{unit_flags: flags}) when is_integer(flags), do: flags
  defp unit_flags(_template), do: 0

  defp type_flags(%Mangos.CreatureTemplate{creature_type_flags: flags}) when is_integer(flags) do
    if (flags &&& @static_flag_visible_to_ghosts) == 0 do
      flags &&& @creature_type_flag_ghost_visible
    else
      @creature_type_flag_ghost_visible
    end
  end

  defp regenerate_stats(%Mangos.CreatureTemplate{regenerate_stats: stats}) when is_integer(stats), do: stats

  defp regenerate_stats(%Mangos.CreatureTemplate{creature_type_flags: flags}) when is_integer(flags) do
    if (flags &&& @static_flag_no_automatic_regen) == 0, do: 0x3, else: 0x0
  end

  defp regenerate_stats(_template), do: 0x3

  defp respawn_delay_ms(%Mangos.Creature{spawntimesecsmin: min, spawntimesecsmax: max})
       when is_integer(min) and is_integer(max) and min >= 0 and max > min do
    (min + :rand.uniform(max - min + 1) - 1) * 1_000
  end

  defp respawn_delay_ms(%Mangos.Creature{spawntimesecs: seconds}) when is_integer(seconds) do
    respawn_delay_ms(seconds)
  end

  defp respawn_delay_ms(%Mangos.Creature{spawntimesecsmin: seconds}) do
    respawn_delay_ms(seconds)
  end

  defp respawn_delay_ms(seconds) when is_integer(seconds) and seconds >= 0 do
    seconds * 1_000
  end

  defp respawn_delay_ms(_seconds), do: @default_respawn_delay_ms

  defp spawn_distance(%Mangos.Creature{spawndist: distance}) when is_number(distance), do: distance
  defp spawn_distance(%Mangos.Creature{wander_distance: distance}) when is_number(distance), do: distance
  defp spawn_distance(_creature), do: 0.0

  defp respawn_unit(%Spawn{unit: %Unit{} = unit}, _current_unit), do: unit

  defp respawn_unit(%Spawn{}, %Unit{} = unit) do
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

  defp respawn_movement_block(%Spawn{movement_block: %MovementBlock{} = movement_block}, _current_movement_block) do
    movement_block
  end

  defp respawn_movement_block(%Spawn{position: {x, y, z}}, %MovementBlock{} = movement_block) do
    %{movement_block | position: {x, y, z, 0.0}, movement_flags: 0}
  end

  defp respawn_movement_block(%Spawn{}, %MovementBlock{} = movement_block) do
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

  defp virtual_item_info_for(%Mangos.ItemTemplate{
         class: class,
         subclass: subclass,
         material: material,
         inventory_type: inventory_type,
         sheath: sheath_type
       }) do
    <<class, subclass, material, inventory_type, sheath_type, 0, 0, 0>>
  end

  defp virtual_item_info_for(nil), do: <<0::64>>

  defp item_display_id(%Mangos.ItemTemplate{display_id: id}), do: id
  defp item_display_id(nil), do: 0

  defp normalize_model_value(%Mangos.CreatureModelInfo{} = model_info, key, default) do
    case Map.get(model_info, key) do
      value when is_number(value) and value > 0 -> value
      _ -> default
    end
  end

  defp normalize_model_value(_model_info, _key, default), do: default
end
