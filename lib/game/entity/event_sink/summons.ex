defmodule ThistleTea.Game.Entity.EventSink.Summons do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Ritual
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.DynamicObject, as: DataDynamicObject
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate, as: DataGameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.DynamicObject, as: DynamicObjectServer
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Summon, as: SummonLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  @summon_unique_default_range 50.0
  @corpse_counting_despawn_types [3, 4, 8]

  def emit(
        %{object: %{guid: caster_guid}, internal: %Internal{world: world}} = entity,
        %Effects.SpawnAreaEffect{} = effect,
        _context
      ) do
    radius =
      case effect.effect do
        %{radius_yards: radius} when is_number(radius) and radius > 0 -> radius
        _ -> 8.0
      end

    dynamic_object = DataDynamicObject.build(caster_guid, world, effect.spell, effect.position, radius)

    World.start_entity(%{
      entity: dynamic_object,
      duration_ms: effect.duration_ms,
      tick: DynamicObjectServer.tick_config(entity, effect.spell, effect.effect)
    })

    entity
  end

  def emit(entity, %Effects.SpawnAreaEffect{}, _context), do: entity

  def emit(
        %Character{object: %{guid: caster_guid}, internal: %Internal{world: world}} = entity,
        %Effects.SpawnFarsight{spell: %Spell{} = spell, position: position, duration_ms: duration_ms},
        context
      ) do
    dynamic_object = DataDynamicObject.build(caster_guid, world, spell, position, 0.0)

    World.start_entity(%{
      entity: dynamic_object,
      duration_ms: duration_ms,
      farsight_owner_guid: caster_guid
    })

    Entity.request_update_from(dynamic_object.object.guid, caster_guid)
    Context.send(context, %Commands.FarsightStarted{guid: dynamic_object.object.guid})
    entity
  end

  def emit(entity, %Effects.SpawnFarsight{}, _context), do: entity

  def emit(%{object: %{guid: caster_guid}} = entity, %Effects.DespawnAreaEffects{spell_id: spell_id}, _context)
      when is_integer(caster_guid) do
    caster_guid
    |> AreaEffects.pids(spell_id)
    |> Enum.each(&World.stop_entity/1)

    entity
  end

  def emit(entity, %Effects.DespawnAreaEffects{}, _context), do: entity

  def emit(entity, %Effects.DespawnEntity{target_guid: guid}, _context) when is_integer(guid) do
    World.stop_entity(guid)
    entity
  end

  def emit(entity, %Effects.DespawnEntity{}, _context), do: entity

  def emit(entity, %Effects.LeaveRitual{target_guid: game_object_guid, source_guid: user_guid}, _context) do
    Entity.leave_ritual(game_object_guid, user_guid)
    entity
  end

  def emit(
        %{
          object: %{guid: owner_guid},
          internal: %Internal{world: world},
          movement_block: %{position: {_x, _y, _z, _o} = source_position}
        } = entity,
        %Effects.SummonGameObject{entry: entry, duration_ms: duration_ms} = effect,
        context
      ) do
    position = summon_position(effect.position, source_position)

    case GameObjectTemplateLoader.get(entry) do
      %DataGameObjectTemplate{} = template ->
        game_object =
          GameObject.build_summoned(template, world, position,
            summoned_by: owner_guid,
            level: owner_level(entity),
            despawn_in_ms: duration_ms,
            ritual_target_guid: effect.target_guid,
            ritual_zone_id: zone_id(world, position)
          )

        World.start_entity(game_object)
        maybe_track_channel_game_object(game_object, context)
        entity

      _ ->
        entity
    end
  end

  def emit(entity, %Effects.SummonGameObject{}, _context), do: entity

  def emit(
        entity,
        %Effects.SummonRequest{
          source_guid: summoner_guid,
          target_guid: target_guid,
          amount: zone_id,
          position: {world, x, y, z}
        },
        _context
      ) do
    Entity.request_summon(target_guid, summoner_guid, zone_id, world, {x, y, z})
    entity
  end

  def emit(entity, %Effects.SummonRequest{}, _context), do: entity

  def emit(%{internal: %Internal{world: world}} = entity, %Effects.SummonCreature{summon: summon} = effect, _context) do
    with true <- summon_allowed?(world, summon),
         %Mob{} = mob <-
           SummonLoader.build(summon.entry, world, summon.position,
             despawn_type: summon.despawn_type,
             despawn_delay_ms: summon.despawn_delay_ms,
             run?: summon.run?
           ),
         mob = put_summon_owner(mob, summon),
         mob = maybe_possess_summon(mob, entity, summon),
         {:ok, pid} <- MobLoader.start_mob(mob) do
      if is_integer(effect.target_guid) and effect.target_guid > 0 and summon.attack_target != nil do
        send(pid, {:force_attack, effect.target_guid})
      end

      if effect.steps != [] do
        send(pid, {:ai_script_steps, effect.steps, effect.target_guid})
      end

      cast_post_spawn_spells(entity, mob.object.guid, summon)
      notify_possession_granted(entity, mob, summon)
    end

    entity
  end

  def emit(entity, %Effects.SummonCreature{}, _context), do: entity

  def emit(entity, %Effects.ControlGranted{} = effect, _context) do
    case {Entity.pid(effect.source_guid), Entity.pid(effect.target_guid)} do
      {owner_pid, controlled_pid} when is_pid(owner_pid) and is_pid(controlled_pid) ->
        attachment = %Attachment{
          kind: effect.kind,
          entity_ref: %EntityRef{
            guid: effect.target_guid,
            entry: Guid.entry(effect.target_guid),
            spell_id: effect.spell_id
          },
          pid: controlled_pid,
          spells: effect.spells
        }

        send(owner_pid, attachment)

      _ ->
        nil
    end

    entity
  end

  def emit(entity, %Effects.ControlReleased{} = effect, _context) do
    case Entity.pid(effect.source_guid) do
      pid when is_pid(pid) -> send(pid, {:control_released, effect.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ReleaseControlled{} = effect, _context) do
    case Entity.pid(effect.target_guid) do
      pid when is_pid(pid) -> send(pid, {:release_control, effect.source_guid, effect.spell_id})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ViewpointGranted{} = effect, _context) do
    case Entity.pid(effect.source_guid) do
      pid when is_pid(pid) -> send(pid, {:viewpoint_granted, effect.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ViewpointReleased{} = effect, _context) do
    case Entity.pid(effect.source_guid) do
      pid when is_pid(pid) -> send(pid, {:viewpoint_released, effect.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(%Character{} = entity, %Effects.SummonPet{entry: entry, spell_id: spell_id}, context) do
    with %Mob{} = built_pet <- SummonLoader.build_pet(entry, entity),
         pet = %{built_pet | unit: %{built_pet.unit | created_by_spell: spell_id}},
         {:ok, pid} <- MobLoader.start_mob(pet) do
      case context do
        %Context{owner_pid: owner_pid} ->
          send(pid, {:attach_pet, owner_pid, spell_id, Map.values(pet.internal.spellbook)})

        nil ->
          World.stop_entity(pet.object.guid)
      end
    end

    entity
  end

  def emit(entity, %Effects.SummonPet{}, _context), do: entity

  def emit(%Mob{object: %{guid: guid}} = entity, %Effects.TameCreature{source_guid: owner_guid, entry: entry}, _context) do
    case Entity.pid(owner_guid) do
      pid when is_pid(pid) -> send(pid, {:tame_pet, entry})
      _ -> nil
    end

    World.stop_entity(guid)
    entity
  end

  def emit(entity, %Effects.TameCreature{}, _context), do: entity

  def emit(entity, %Effects.DismissPet{target_guid: pet_guid}, _context) when is_integer(pet_guid) and pet_guid > 0 do
    World.stop_entity(pet_guid)
    entity
  end

  def emit(
        %Character{
          object: %{guid: owner_guid},
          internal: %Internal{world: world},
          movement_block: %{position: position}
        } = entity,
        %Effects.SummonTotem{entry: entry, slot: slot, duration_ms: duration_ms},
        context
      ) do
    old_guid = Map.get(entity.internal.totem_guids, slot)
    if is_integer(old_guid), do: World.stop_entity(old_guid)

    with %Mob{} = built <-
           SummonLoader.build(entry, world, position, despawn_type: 1, despawn_delay_ms: duration_ms),
         built = SummonLoader.attach_owner(built, owner_guid),
         unit = %{
           built.unit
           | faction_template: entity.unit.faction_template,
             level: entity.unit.level
         },
         totem = %{
           built
           | unit: unit,
             internal: %{
               built.internal
               | rooted?: true,
                 totem: %Totem{owner_guid: owner_guid}
             }
         },
         {:ok, _pid} <- MobLoader.start_mob(totem) do
      Context.send(context, %Commands.TotemStarted{slot: slot, guid: totem.object.guid})
      entity
    else
      _ -> entity
    end
  end

  def emit(entity, %Effects.SummonTotem{}, _context), do: entity

  def emit(entity, %Effects.DespawnSelf{} = effect, context) do
    Context.send_after(context, {:despawn_creature, effect.respawn_delay_ms}, effect.duration_ms || 0)
    entity
  end

  def emit(entity, %Effects.RespawnSelf{even_if_alive?: even_if_alive?}, context) do
    Context.send(context, {:script_respawn, even_if_alive?})
    entity
  end

  defp summon_position({x, y, z, orientation}, {source_x, source_y, source_z, source_orientation}) do
    {
      coordinate(x, source_x),
      coordinate(y, source_y),
      coordinate(z, source_z),
      coordinate(orientation, source_orientation)
    }
  end

  defp summon_position(_position, source_position), do: source_position

  defp coordinate(value, _fallback) when is_number(value) and value != 0, do: value
  defp coordinate(_value, fallback), do: fallback

  defp maybe_track_channel_game_object(
         %GameObject{object: %{guid: guid}, internal: %Internal{ritual: %Ritual{}}},
         context
       ) do
    Context.send(context, %Commands.ChannelGameObjectStarted{guid: guid})
  end

  defp maybe_track_channel_game_object(%GameObject{}, _context), do: :ok

  defp owner_level(%{unit: %{level: level}}) when is_integer(level), do: level
  defp owner_level(_entity), do: 1

  defp zone_id(%{map_id: map_id}, {x, y, z, _orientation}) do
    case Pathfinding.get_zone_and_area(map_id, {x, y, z}) do
      {zone_id, _area_id} -> zone_id
      _missing -> 0
    end
  end

  defp summon_allowed?(map, %{unique?: true, entry: entry, position: {x, y, z, _o}} = summon) do
    limit = max(summon.unique_limit, 1)
    range = if summon.unique_distance > 0, do: summon.unique_distance, else: @summon_unique_default_range
    count_dead? = summon.despawn_type in @corpse_counting_despawn_types

    existing =
      map
      |> World.nearby_mobs_at({x, y, z}, range)
      |> Enum.count(fn {guid, _distance} ->
        Guid.entry(guid) == entry and (count_dead? or summon_alive?(guid))
      end)

    existing < limit
  end

  defp summon_allowed?(_map, _summon), do: true

  defp summon_alive?(guid) do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: false} -> false
      _ -> true
    end
  end

  defp put_summon_owner(%Mob{} = mob, %{owner_guid: owner_guid}) when is_integer(owner_guid) do
    SummonLoader.attach_owner(mob, owner_guid)
  end

  defp put_summon_owner(%Mob{} = mob, _summon), do: mob

  defp maybe_possess_summon(%Mob{} = mob, entity, %{control: :possessed, control_spell_id: spell_id}) do
    SummonLoader.possess(mob, entity, spell_id)
  end

  defp maybe_possess_summon(%Mob{} = mob, _entity, _summon), do: mob

  defp notify_possession_granted(entity, %Mob{object: %{guid: guid}, internal: %Internal{spellbook: spellbook}}, %{
         control: :possessed,
         control_spell_id: spell_id
       }) do
    spells = (spellbook || %{}) |> Map.values() |> Enum.reject(&Spell.attribute?(&1, :passive))

    emit(entity, Effects.control_granted(entity.object.guid, guid, spell_id, spells, kind: :possession), nil)

    :ok
  end

  defp notify_possession_granted(_entity, _mob, _summon), do: :ok

  defp cast_post_spawn_spells(entity, summon_guid, %{post_spawn_spells: spells}) when is_list(spells) do
    Enum.each(spells, fn
      %{caster: :owner, spell_id: spell_id} ->
        with %Spell{} = spell <- SpellLoader.load(spell_id) do
          Entity.receive_spell(summon_guid, CastContext.from_caster(entity, spell, summon_guid), spell)
        end

      %{caster: :summon, spell_id: spell_id, resolve_targets?: resolve_targets?} ->
        Entity.trigger_spell(summon_guid, spell_id, summon_guid, resolve_targets?: resolve_targets?)

      _ ->
        nil
    end)
  end

  defp cast_post_spawn_spells(_entity, _summon_guid, _summon), do: :ok
end
