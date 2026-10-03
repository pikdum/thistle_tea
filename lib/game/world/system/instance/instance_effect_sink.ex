defmodule ThistleTea.Game.World.System.Instance.InstanceEffectSink do
  @moduledoc """
  Projects typed instance-script effects into owners in one exact world copy.
  """

  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Loader.BroadcastText
  alias ThistleTea.Game.World.Loader.GameObject, as: GameObjectLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Summon, as: SummonLoader
  alias ThistleTea.Game.World.System.SpawnPool

  def emit(world, effect, options \\ [])

  def emit(%WorldRef{} = world, %Effects.RespawnGameObject{} = effect, options) do
    blueprint = Keyword.get(options, :game_object_blueprint, &GameObjectLoader.cached_blueprint/1)
    respawn = Keyword.get(options, :respawn_game_object, &SpawnPool.respawn_game_object/3)

    case blueprint.(effect.db_guid) do
      nil -> :ok
      found -> respawn.(world, found, effect.duration_ms)
    end

    :ok
  end

  def emit(%WorldRef{} = world, %Effects.LoadCreatureSpawns{db_guids: db_guids}, options) do
    blueprints = Keyword.get(options, :creature_blueprints, &MobLoader.blueprints/1)
    load = Keyword.get(options, :load_creature, &SpawnPool.load_creature/2)

    db_guids
    |> blueprints.()
    |> Map.values()
    |> Enum.each(&load.(world, &1))

    :ok
  end

  def emit(%WorldRef{} = world, %Effects.RunCreatureScript{within: {center, radius}} = effect, options) do
    guids = Keyword.get(options, :guids, &World.guids/1)
    position = Keyword.get(options, :position, &World.position/1)

    nearby = fn world ->
      world
      |> guids.()
      |> Enum.filter(fn guid ->
        Guid.entity_type(guid) == :mob and World.entry(guid) == effect.creature_entry and
          within?(position.(guid), world, center, radius)
      end)
    end

    emit(world, %{effect | within: nil}, Keyword.put(options, :guids, nearby))
  end

  def emit(%WorldRef{} = world, effect, options) do
    guids = Keyword.get(options, :guids, &World.guids/1)
    dispatch = Keyword.get(options, :dispatch, &dispatch/1)
    summon = Keyword.get(options, :summon, &summon/2)
    spawn_guid = Keyword.get(options, :spawn_guid, &World.spawn_guid/3)
    broadcast_text = Keyword.get(options, :broadcast_text, &BroadcastText.get/1)

    project(world, effect, guids, dispatch, summon, spawn_guid, broadcast_text)
  end

  defp project(world, %Effects.OperateGameObject{} = effect, guids, dispatch, _summon, _spawn_guid, _text) do
    world
    |> entity_guids(:game_object, effect.entry, guids)
    |> Enum.each(&dispatch.({:operate_game_object, &1, effect.action}))
  end

  defp project(world, %Effects.SummonCreature{} = effect, _guids, _dispatch, summon, _spawn_guid, _text) do
    summon.(world, effect)
    :ok
  end

  defp project(world, %Effects.MonsterTalk{} = effect, guids, dispatch, _summon, _spawn_guid, text) do
    case text.(effect.broadcast_text_id) do
      %{text: message, chat_type: chat_type} ->
        world
        |> targeted_creature_guids(effect, guids, nil)
        |> Enum.each(&dispatch.({:monster_talk, &1, message, chat_type}))

      _missing ->
        :ok
    end
  end

  defp project(world, %Effects.CastPlayerSpell{} = effect, guids, dispatch, _summon, _spawn_guid, _text) do
    world |> entity_guids(:player, nil, guids) |> Enum.each(&dispatch.({:cast_player_spell, &1, effect.spell_id}))
  end

  defp project(world, %Effects.RemovePlayerAuras{} = effect, guids, dispatch, _summon, _spawn_guid, _text) do
    world |> entity_guids(:player, nil, guids) |> Enum.each(&dispatch.({:remove_player_auras, &1, effect.spell_ids}))
  end

  defp project(world, %Effects.QuestKillCredit{} = effect, guids, dispatch, _summon, _spawn_guid, _text) do
    world |> entity_guids(:player, nil, guids) |> Enum.each(&dispatch.({:quest_kill_credit, &1, effect.creature_entry}))
  end

  defp project(world, %Effects.ModifyCreatureNpcFlags{} = effect, guids, dispatch, _summon, _spawn_guid, _text) do
    world
    |> entity_guids(:mob, effect.creature_entry, guids)
    |> Enum.each(&dispatch.({:modify_creature_npc_flags, &1, effect.flags, effect.mode}))
  end

  defp project(world, %Effects.ModifyCreatureUnitFlags{} = effect, guids, dispatch, _summon, _spawn_guid, _text) do
    world
    |> entity_guids(:mob, effect.creature_entry, guids)
    |> Enum.each(&dispatch.({:modify_creature_unit_flags, &1, effect.flags, effect.mode}))
  end

  defp project(world, %Effects.MoveCreature{} = effect, guids, dispatch, _summon, spawn_guid, _text) do
    {x, y, z} = effect.position

    world
    |> targeted_creature_guids(effect, guids, spawn_guid)
    |> Enum.each(fn guid ->
      if effect.opts == [],
        do: dispatch.({:move_creature, guid, {x, y, z}}),
        else: dispatch.({:move_creature, guid, {x, y, z}, effect.opts})
    end)
  end

  defp project(world, %Effects.TriggerCreatureSpell{} = effect, guids, dispatch, _summon, spawn_guid, _text) do
    world
    |> targeted_creature_guids(effect, guids, spawn_guid)
    |> Enum.each(&dispatch.({:trigger_creature_spell, &1, effect.spell_id}))
  end

  defp project(world, %Effects.RunCreatureScript{} = effect, guids, dispatch, _summon, spawn_guid, _text) do
    world
    |> targeted_creature_guids(effect, guids, spawn_guid)
    |> Enum.each(&dispatch.({:run_creature_script, &1, effect.steps, world}))
  end

  defp targeted_creature_guids(_world, %{creature_guid: guid}, _guids, _spawn_guid) when is_integer(guid), do: [guid]

  defp targeted_creature_guids(world, %{creature_db_guid: db_guid}, _guids, spawn_guid)
       when is_integer(db_guid) and is_function(spawn_guid, 3) do
    case spawn_guid.(world, :mob, db_guid) do
      guid when is_integer(guid) -> [guid]
      _missing -> []
    end
  end

  defp targeted_creature_guids(world, effect, guids, _spawn_guid),
    do: entity_guids(world, :mob, effect.creature_entry, guids)

  defp within?({world, x, y, z}, world, {cx, cy, cz}, radius),
    do: (x - cx) * (x - cx) + (y - cy) * (y - cy) + (z - cz) * (z - cz) <= radius * radius

  defp within?(_position, _world, _center, _radius), do: false

  defp entity_guids(world, entity_type, entry, guids) do
    world
    |> guids.()
    |> Enum.filter(fn guid ->
      Guid.entity_type(guid) == entity_type and (is_nil(entry) or World.entry(guid) == entry)
    end)
  end

  defp dispatch({:operate_game_object, guid, action}), do: Entity.operate_game_object(guid, action)

  defp dispatch({:monster_talk, guid, text, chat_type}), do: Entity.monster_talk(guid, text, chat_type)

  defp dispatch({:cast_player_spell, guid, spell_id}), do: Entity.trigger_spell(guid, spell_id, guid, triggered: true)

  defp dispatch({:remove_player_auras, guid, spell_ids}), do: Entity.remove_spell_auras(guid, spell_ids)
  defp dispatch({:quest_kill_credit, guid, entry}), do: Entity.quest_kill_credit(guid, entry)

  defp dispatch({:modify_creature_npc_flags, guid, flags, mode}), do: Entity.modify_npc_flags(guid, flags, mode)
  defp dispatch({:modify_creature_unit_flags, guid, flags, mode}), do: Entity.modify_unit_flags(guid, flags, mode)

  defp dispatch({:move_creature, guid, position}), do: Entity.move_to(guid, position)
  defp dispatch({:move_creature, guid, position, opts}), do: Entity.move_to(guid, position, opts)

  defp dispatch({:trigger_creature_spell, guid, spell_id}),
    do: Entity.trigger_spell(guid, spell_id, guid, triggered: true)

  defp dispatch({:run_creature_script, guid, steps, world}), do: Entity.start_script(guid, steps, guid, world)

  defp summon(world, %Effects.SummonCreature{} = effect) do
    opts = [despawn_type: effect.despawn_type, despawn_delay_ms: effect.despawn_delay_ms]

    with %Mob{object: %{guid: guid}} = mob <- SummonLoader.build(effect.entry, world, effect.position, opts),
         {:ok, _pid} <- MobLoader.start_mob(mob) do
      if is_tuple(effect.move_to), do: Entity.move_to(guid, effect.move_to)
      if effect.steps != [], do: Entity.start_script(guid, effect.steps, guid, world)
      :ok
    else
      _error -> :ok
    end
  end
end
