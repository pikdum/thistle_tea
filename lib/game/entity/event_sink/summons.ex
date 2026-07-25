defmodule ThistleTea.Game.Entity.EventSink.Summons do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Ritual
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.DynamicObject, as: DataDynamicObject
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate, as: DataGameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.DynamicObject, as: DynamicObjectServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
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
        %Effects.SpawnAreaEffect{} = effect
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

  def emit(entity, %Effects.SpawnAreaEffect{}), do: entity

  def emit(
        %Character{object: %{guid: caster_guid}, player: player, internal: %Internal{world: world}} = entity,
        %Effects.SpawnFarsight{spell: %Spell{} = spell, position: position, duration_ms: duration_ms}
      ) do
    dynamic_object = DataDynamicObject.build(caster_guid, world, spell, position, 0.0)

    World.start_entity(%{
      entity: dynamic_object,
      duration_ms: duration_ms,
      farsight_owner_guid: caster_guid
    })

    Entity.request_update_from(dynamic_object.object.guid, caster_guid)
    send(self(), {:viewpoint_granted, dynamic_object.object.guid})

    %{entity | player: %{player | farsight: dynamic_object.object.guid}}
    |> Core.mark_broadcast_update()
  end

  def emit(entity, %Effects.SpawnFarsight{}), do: entity

  def emit(%{object: %{guid: caster_guid}} = entity, %Effects.DespawnAreaEffects{spell_id: spell_id})
      when is_integer(caster_guid) do
    caster_guid
    |> AreaEffects.pids(spell_id)
    |> Enum.each(&World.stop_entity/1)

    entity
  end

  def emit(entity, %Effects.DespawnAreaEffects{}), do: entity

  def emit(entity, %Effects.DespawnEntity{target_guid: guid}) when is_integer(guid) do
    World.stop_entity(guid)
    entity
  end

  def emit(entity, %Effects.DespawnEntity{}), do: entity

  def emit(entity, %Effects.LeaveRitual{target_guid: game_object_guid, source_guid: user_guid}) do
    Entity.leave_ritual(game_object_guid, user_guid)
    entity
  end

  def emit(
        %{
          object: %{guid: owner_guid},
          internal: %Internal{world: world},
          movement_block: %{position: {_x, _y, _z, _o} = position}
        } = entity,
        %Effects.SummonGameObject{entry: entry, duration_ms: duration_ms} = effect
      ) do
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

        track_channel_game_object(entity, game_object)

      _ ->
        entity
    end
  end

  def emit(entity, %Effects.SummonGameObject{}), do: entity

  def emit(entity, %Effects.SummonRequest{
        source_guid: summoner_guid,
        target_guid: target_guid,
        amount: zone_id,
        position: {world, x, y, z}
      }) do
    Entity.request_summon(target_guid, summoner_guid, zone_id, world, {x, y, z})
    entity
  end

  def emit(entity, %Effects.SummonRequest{}), do: entity

  def emit(%{internal: %Internal{world: world}} = entity, %Effects.SummonCreature{summon: summon} = effect) do
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

  def emit(entity, %Effects.SummonCreature{}), do: entity

  def emit(entity, %Effects.ControlGranted{} = effect) do
    case Entity.pid(effect.source_guid) do
      pid when is_pid(pid) ->
        send(pid, {:control_granted, effect.target_guid, effect.spell_id, effect.spells, effect.enabled?})

      _ ->
        nil
    end

    entity
  end

  def emit(entity, %Effects.ControlReleased{} = effect) do
    case Entity.pid(effect.source_guid) do
      pid when is_pid(pid) -> send(pid, {:control_released, effect.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ReleaseControlled{} = effect) do
    case Entity.pid(effect.target_guid) do
      pid when is_pid(pid) -> send(pid, {:release_control, effect.source_guid, effect.spell_id})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ViewpointGranted{} = effect) do
    case Entity.pid(effect.source_guid) do
      pid when is_pid(pid) -> send(pid, {:viewpoint_granted, effect.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ViewpointReleased{} = effect) do
    case Entity.pid(effect.source_guid) do
      pid when is_pid(pid) -> send(pid, {:viewpoint_released, effect.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(%Character{} = entity, %Effects.SummonPet{entry: entry, spell_id: spell_id}) do
    with %Mob{} = built_pet <- SummonLoader.build_pet(entry, entity),
         pet = %{built_pet | unit: %{built_pet.unit | created_by_spell: spell_id}},
         {:ok, pid} <- MobLoader.start_mob(pet) do
      old_pet_guid = entity.unit.summon

      if is_integer(old_pet_guid) and old_pet_guid > 0 and old_pet_guid != pet.object.guid do
        World.stop_entity(old_pet_guid)
      end

      send(pid, {:attach_pet, self(), spell_id, Map.values(pet.internal.spellbook)})
    end

    entity
  end

  def emit(entity, %Effects.SummonPet{}), do: entity

  def emit(%Mob{object: %{guid: guid}} = entity, %Effects.TameCreature{source_guid: owner_guid, entry: entry}) do
    case Entity.pid(owner_guid) do
      pid when is_pid(pid) -> send(pid, {:tame_pet, entry})
      _ -> nil
    end

    World.stop_entity(guid)
    entity
  end

  def emit(entity, %Effects.TameCreature{}), do: entity

  def emit(%Character{unit: %Unit{summon: pet_guid}} = entity, %Effects.DismissPet{} = effect)
      when is_integer(pet_guid) and pet_guid > 0 do
    World.stop_entity(pet_guid)
    Network.send_packet(Message.SmsgPetSpells.clear())

    internal =
      if effect.reason == :owner_died do
        entity.internal
      else
        %{entity.internal | active_pet_entry: nil, active_pet_spell_id: nil}
      end

    %{entity | unit: %{entity.unit | summon: 0}, internal: internal}
  end

  def emit(entity, %Effects.DismissPet{}), do: entity

  def emit(
        %Character{
          object: %{guid: owner_guid},
          internal: %Internal{world: world},
          movement_block: %{position: position}
        } = entity,
        %Effects.SummonTotem{entry: entry, slot: slot, duration_ms: duration_ms}
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
      totem_guids = Map.put(entity.internal.totem_guids, slot, totem.object.guid)
      %{entity | internal: %{entity.internal | totem_guids: totem_guids}}
    else
      _ -> entity
    end
  end

  def emit(entity, %Effects.SummonTotem{}), do: entity

  def emit(entity, %Effects.DespawnSelf{} = effect) do
    Process.send_after(self(), {:despawn_creature, effect.respawn_delay_ms}, effect.duration_ms || 0)
    entity
  end

  defp track_channel_game_object(%{internal: %Internal{} = internal, unit: %Unit{} = unit} = entity, %GameObject{
         object: %{guid: guid},
         internal: %Internal{ritual: %Ritual{}}
       }) do
    %{
      entity
      | internal: %{internal | channel_game_object_guid: guid, channel_game_object_owned?: true},
        unit: %{unit | channel_object: guid}
    }
    |> Core.mark_broadcast_update()
  end

  defp track_channel_game_object(entity, %GameObject{}), do: entity

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

    emit(entity, Effects.control_granted(entity.object.guid, guid, spell_id, spells, possess?: true))

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
