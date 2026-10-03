defmodule ThistleTea.Game.World.Entity.EventSink.Summons do
  @moduledoc false

  alias ThistleTea.Game.Core.AI.BT.WaypointHold
  alias ThistleTea.Game.Core.Creature.CharmSpells
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Commands
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.DynamicObject, as: DynamicObjectCore
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.Totems
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Modifiers
  alias ThistleTea.Game.Core.Spell.Radius
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.DynamicObject, as: DynamicObjectServer
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.GameObjectSummons
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Summon, as: SummonLoader
  alias ThistleTea.Game.World.Loader.Totem, as: TotemLoader
  alias ThistleTea.Game.World.Loader.WildSummon
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.SpawnPool

  @summon_unique_default_range 50.0
  @corpse_counting_despawn_types [3, 4, 8]

  def emit(
        %{object: %{guid: caster_guid}, internal: %Internal{world: world}} = entity,
        %Effects.SpawnAreaEffect{} = effect,
        _context
      ) do
    radius = effect.radius_yards || Radius.effect(effect.effect, Modifiers.snapshot(entity, effect.spell), 8.0)

    dynamic_object = DynamicObjectCore.build(caster_guid, world, effect.spell, effect.position, radius)

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
    dynamic_object = DynamicObjectCore.build(caster_guid, world, spell, position, 0.0)

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

  def emit(%{object: %{guid: caster_guid}} = entity, %Effects.DelayAreaEffects{} = effect, _context)
      when is_integer(caster_guid) do
    caster_guid
    |> AreaEffects.pids(effect.spell_id)
    |> Enum.each(&DynamicObjectServer.delay(&1, effect.delay_ms))

    entity
  end

  def emit(entity, %Effects.DelayAreaEffects{}, _context), do: entity

  def emit(entity, %Effects.DespawnEntity{target_guid: guid}, _context) when is_integer(guid) do
    World.stop_entity(guid)
    entity
  end

  def emit(entity, %Effects.DespawnEntity{}, _context), do: entity

  def emit(entity, %Effects.RemoveSelf{respawn_delay_ms: respawn_delay_ms}, context) do
    Context.send(context, {:script_remove_object, respawn_delay_ms})
    entity
  end

  def emit(entity, %Effects.ActivateGameObject{user_guid: user_guid}, context) do
    Context.send(context, {:script_activate_object, user_guid})
    entity
  end

  def emit(entity, %Effects.ApplyGameObjectAction{target_guid: guid} = effect, _context) do
    Entity.apply_game_object_action(guid, effect)
    entity
  end

  def emit(entity, %Effects.RestoreGameObject{revision: revision, state: state, delay_ms: delay}, context) do
    Context.send_after(context, {:restore_game_object, revision, state}, delay)
    entity
  end

  def emit(entity, %Effects.FinishGameObjectUse{revision: revision, delay_ms: delay}, context) do
    Context.send_after(context, {:finish_game_object_use, revision}, delay)
    entity
  end

  def emit(
        %{internal: %Internal{world: world}} = entity,
        %Effects.RespawnGameObject{blueprint: %GameObject{} = blueprint, duration_ms: duration_ms},
        _context
      ) do
    SpawnPool.respawn_game_object(world, blueprint, duration_ms)
    entity
  end

  def emit(
        %{internal: %Internal{world: world}} = entity,
        %Effects.DespawnGameObject{blueprint: %GameObject{} = blueprint, respawn_delay_ms: respawn_delay_ms},
        _context
      ) do
    SpawnPool.suspend_game_object(world, blueprint, respawn_delay_ms)
    entity
  end

  def emit(
        %{internal: %Internal{world: world}} = entity,
        %Effects.LoadGameObjectSpawn{blueprint: %GameObject{} = blueprint},
        _context
      ) do
    SpawnPool.load_game_object(world, blueprint)
    entity
  end

  def emit(%{internal: %Internal{world: world}} = entity, %Effects.LoadCreatureSpawn{db_guid: db_guid}, _context) do
    case MobLoader.blueprints([db_guid]) do
      %{{:creature, ^db_guid} => %Mob{} = blueprint} -> SpawnPool.load_creature(world, blueprint)
      _missing -> :ok
    end

    entity
  end

  def emit(
        %{internal: %Internal{world: world}} = entity,
        %Effects.OperateGameObject{
          action: action,
          reset_delay_ms: reset_delay_ms,
          blueprint: %GameObject{} = blueprint
        },
        _context
      ) do
    SpawnPool.operate_game_object(world, blueprint, action, reset_delay_ms)
    entity
  end

  def emit(entity, %Effects.OperateGameObject{action: action, reset_delay_ms: reset_delay_ms, blueprint: nil}, context) do
    Context.send(context, {:script_operate_game_object, action, reset_delay_ms})
    entity
  end

  def emit(entity, %Effects.LeaveRitual{target_guid: game_object_guid, source_guid: user_guid}, _context) do
    Entity.leave_ritual(game_object_guid, user_guid)
    entity
  end

  def emit(entity, %Effects.SummonGameObject{owned?: true} = effect, context) do
    Context.send(context, GameObjectSummons.prepare(entity, effect))
    entity
  end

  def emit(entity, %Effects.SummonGameObject{owned?: false} = effect, context) do
    GameObjectSummons.start(entity, effect, context)
    entity
  end

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
           SummonLoader.build(summon.entry, world, scattered_position(world, summon),
             summoner_guid: entity.object.guid,
             despawn_type: summon.despawn_type,
             despawn_delay_ms: summon.despawn_delay_ms,
             run?: summon.run?,
             concealed?: Map.get(summon, :concealed?),
             home: Map.get(summon, :home),
             wander_distance: Map.get(summon, :wander_distance)
           ),
         mob = put_summon_owner(mob, summon),
         mob = maybe_possess_summon(mob, entity, summon),
         {:ok, pid} <- MobLoader.start_mob(mob) do
      case Map.get(summon, :attack_guid) do
        attack_guid when is_integer(attack_guid) and attack_guid > 0 -> send(pid, {:force_attack, attack_guid})
        _none -> :ok
      end

      if effect.steps != [] do
        send(pid, {:ai_script_steps, effect.steps, effect.target_guid})
      end

      cast_post_spawn_spells(entity, mob.object.guid, summon)
      notify_possession_granted(entity, mob, summon)
      WaypointHold.track(entity, mob.object.guid)
    else
      _not_summoned -> entity
    end
  end

  def emit(entity, %Effects.SummonCreature{}, _context), do: entity

  def emit(%{unit: _unit} = entity, %Effects.SummonWild{} = effect, _context) do
    now = Time.now()

    for index <- 0..(effect.count - 1) do
      position = wild_position(entity, effect, index)
      entity |> WildSummon.build(effect, position, now) |> MobLoader.start_mob()
    end

    entity
  end

  def emit(entity, %Effects.SummonWild{}, _context), do: entity

  def emit(%{unit: _unit} = entity, %Effects.SummonGuardians{} = effect, context) do
    Context.send(context, effect)
    entity
  end

  def emit(entity, %Effects.SummonGuardians{}, _context), do: entity

  def emit(entity, %Effects.ControlGranted{} = effect, _context) do
    case {Entity.pid(effect.source_guid), Entity.pid(effect.target_guid)} do
      {owner_pid, controlled_pid} when is_pid(owner_pid) and is_pid(controlled_pid) ->
        attachment = %Attachment{
          kind: effect.kind,
          entity_ref: %EntityRef{
            guid: effect.target_guid,
            entry: World.entry(effect.target_guid),
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

  def emit(%Character{} = entity, %Effects.SummonPet{entry: entry, spell_id: spell_id} = effect, context) do
    with %Mob{} = built_pet <- SummonLoader.build_pet(entry, entity),
         built_pet = SummonLoader.with_health_percent(built_pet, effect.health_percent),
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

  def emit(%Mob{} = entity, %Effects.SummonPet{} = effect, context) do
    Context.send(context, effect)
    entity
  end

  def emit(entity, %Effects.SummonPet{}, _context), do: entity

  def emit(entity, %Effects.SummonControlledPet{} = effect, context) do
    Context.send(context, effect)
    entity
  end

  def emit(%Character{} = entity, %Effects.SummonMiniPet{} = effect, context) do
    Context.send(context, effect)
    entity
  end

  def emit(entity, %Effects.SummonMiniPet{}, _context), do: entity

  def emit(%Mob{} = entity, %Effects.TameCreature{source_guid: owner_guid, entry: entry}, context) do
    case Entity.pid(owner_guid) do
      pid when is_pid(pid) -> send(pid, {:tame_pet, entry, entity.unit.level})
      _ -> nil
    end

    Context.send(context, :tame_stop)
    entity
  end

  def emit(entity, %Effects.TameCreature{}, _context), do: entity

  def emit(entity, %Effects.LearnPetSpell{} = effect, context) do
    Context.send(context, effect)
    entity
  end

  def emit(entity, %Effects.DismissPet{target_guid: pet_guid}, _context) when is_integer(pet_guid) and pet_guid > 0 do
    entity = CompanionOwner.suspend_hunter_pet(entity, pet_guid)
    World.stop_entity(pet_guid)
    entity
  end

  def emit(entity, %Effects.PetBroke{target_guid: guid} = effect, context) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> send(pid, effect)
      _ -> Context.send(context, :pet_stop)
    end

    entity
  end

  def emit(entity, %Effects.PetRevived{target_guid: guid} = effect, _context) do
    with :player <- Guid.entity_type(guid), pid when is_pid(pid) <- Entity.pid(guid) do
      send(pid, effect)
    end

    entity
  end

  def emit(entity, %type{target_guid: guid} = effect, _context)
      when type in [
             Effects.PetHappinessChanged,
             Effects.PetProgressChanged,
             Effects.PetReactionChanged,
             Effects.LearnPetRecipe,
             Effects.PetDied
           ] do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> send(pid, effect)
      _ -> :ok
    end

    entity
  end

  def emit(%{internal: %Internal{}} = entity, %Effects.SummonTotem{slot: slot} = effect, _context) do
    old_guid = Map.get(entity.internal.totem_guids, slot)
    if is_integer(old_guid), do: World.stop_entity(old_guid)

    with %Mob{} = totem <- TotemLoader.build(entity, effect, Time.now()),
         {:ok, _pid} <- MobLoader.start_mob(totem) do
      Totems.started(entity, slot, totem.object.guid)
    else
      _ -> entity
    end
  end

  def emit(entity, %Effects.SummonTotem{}, _context), do: entity

  def emit(entity, %Effects.DespawnSelf{} = effect, context) do
    Context.send_after(context, {:despawn_creature, effect.respawn_delay_ms}, effect.duration_ms || 0)
    entity
  end

  def emit(
        %Mob{internal: %Internal{spawn: %{despawn_delay_ms: delay} = spawn} = internal} = entity,
        %Effects.RestartSummonTimer{},
        context
      )
      when is_integer(delay) and delay > 0 do
    ref = make_ref()
    Context.send_after(context, {:summon_despawn, ref}, delay)
    %{entity | internal: %{internal | spawn: %{spawn | despawn_ref: ref}}}
  end

  def emit(entity, %Effects.RestartSummonTimer{}, _context), do: entity

  def emit(entity, %Effects.RespawnSelf{even_if_alive?: even_if_alive?}, context) do
    Context.send(context, {:script_respawn, even_if_alive?})
    entity
  end

  def emit(entity, %Effects.ReviveSelf{life_ms: life_ms}, context) do
    Context.send(context, {:revive_self, life_ms})
    entity
  end

  defp summon_allowed?(map, %{unique?: true, entry: entry, position: {x, y, z, _o}} = summon) do
    limit = max(summon.unique_limit, 1)
    range = if summon.unique_distance > 0, do: summon.unique_distance, else: @summon_unique_default_range
    count_dead? = summon.despawn_type in @corpse_counting_despawn_types

    existing =
      map
      |> World.nearby_mobs_at({x, y, z}, range)
      |> Enum.count(fn {guid, _distance} ->
        World.entry(guid) == entry and (count_dead? or summon_alive?(guid))
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

  defp notify_possession_granted(entity, %Mob{object: %{guid: guid}} = mob, %{
         control: :possessed,
         control_spell_id: spell_id
       }) do
    spells = CharmSpells.bar_spells(mob)

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

  defp scattered_position(world, %{position: {x, y, z, orientation}, scatter: radius} = summon)
       when is_number(radius) and radius > 0 do
    case Pathfinding.find_random_point_around_circle(world.map_id, {x, y, z}, radius) do
      {px, py, pz} -> {px, py, pz, orientation}
      _ -> summon.position
    end
  end

  defp scattered_position(_world, summon), do: summon.position

  defp wild_position(entity, %Effects.SummonWild{scatter?: true, radius_yards: radius} = effect, index)
       when index > 0 and radius > 0 do
    {x, y, z, orientation} = effect.position

    case Pathfinding.find_random_point_around_circle(entity.internal.world.map_id, {x, y, z}, radius) do
      {px, py, pz} -> {px, py, pz, orientation}
      _ -> effect.position
    end
  end

  defp wild_position(_entity, effect, _index), do: effect.position
end
