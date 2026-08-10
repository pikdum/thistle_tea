defmodule ThistleTea.Game.World.InstanceEffectSink do
  @moduledoc """
  Projects typed instance-script effects into owners in one exact world copy.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.InstanceScript.Effects
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.BroadcastText
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Summon, as: SummonLoader
  alias ThistleTea.Game.WorldRef

  def emit(%WorldRef{} = world, effect, options \\ []) do
    guids = Keyword.get(options, :guids, &World.guids/1)
    dispatch = Keyword.get(options, :dispatch, &dispatch/1)
    summon = Keyword.get(options, :summon, &summon/4)
    broadcast_text = Keyword.get(options, :broadcast_text, &BroadcastText.get/1)

    project(world, effect, guids, dispatch, summon, broadcast_text)
  end

  defp project(world, %Effects.OperateGameObject{} = effect, guids, dispatch, _summon, _text) do
    world
    |> entity_guids(:game_object, effect.entry, guids)
    |> Enum.each(&dispatch.({:operate_game_object, &1, effect.action}))
  end

  defp project(world, %Effects.SummonCreature{} = effect, _guids, _dispatch, summon, _text) do
    summon.(world, effect.entry, effect.position, effect.despawn_delay_ms)
    :ok
  end

  defp project(world, %Effects.MonsterTalk{} = effect, guids, dispatch, _summon, text) do
    case text.(effect.broadcast_text_id) do
      %{text: message, chat_type: chat_type} ->
        world
        |> entity_guids(:mob, effect.creature_entry, guids)
        |> Enum.each(&dispatch.({:monster_talk, &1, message, chat_type}))

      _missing ->
        :ok
    end
  end

  defp project(world, %Effects.CastPlayerSpell{} = effect, guids, dispatch, _summon, _text) do
    world |> entity_guids(:player, nil, guids) |> Enum.each(&dispatch.({:cast_player_spell, &1, effect.spell_id}))
  end

  defp project(world, %Effects.RemovePlayerAuras{} = effect, guids, dispatch, _summon, _text) do
    world |> entity_guids(:player, nil, guids) |> Enum.each(&dispatch.({:remove_player_auras, &1, effect.spell_ids}))
  end

  defp project(world, %Effects.QuestKillCredit{} = effect, guids, dispatch, _summon, _text) do
    world |> entity_guids(:player, nil, guids) |> Enum.each(&dispatch.({:quest_kill_credit, &1, effect.creature_entry}))
  end

  defp project(world, %Effects.ModifyCreatureNpcFlags{} = effect, guids, dispatch, _summon, _text) do
    world
    |> entity_guids(:mob, effect.creature_entry, guids)
    |> Enum.each(&dispatch.({:modify_creature_npc_flags, &1, effect.flags, effect.mode}))
  end

  defp project(world, %Effects.ModifyCreatureUnitFlags{} = effect, guids, dispatch, _summon, _text) do
    world
    |> entity_guids(:mob, effect.creature_entry, guids)
    |> Enum.each(&dispatch.({:modify_creature_unit_flags, &1, effect.flags, effect.mode}))
  end

  defp project(world, %Effects.MoveCreature{} = effect, guids, dispatch, _summon, _text) do
    {x, y, z} = effect.position
    world |> entity_guids(:mob, effect.creature_entry, guids) |> Enum.each(&dispatch.({:move_creature, &1, {x, y, z}}))
  end

  defp project(world, %Effects.TriggerCreatureSpell{} = effect, guids, dispatch, _summon, _text) do
    world
    |> targeted_creature_guids(effect, guids)
    |> Enum.each(&dispatch.({:trigger_creature_spell, &1, effect.spell_id}))
  end

  defp targeted_creature_guids(_world, %{creature_guid: guid}, _guids) when is_integer(guid), do: [guid]
  defp targeted_creature_guids(world, effect, guids), do: entity_guids(world, :mob, effect.creature_entry, guids)

  defp entity_guids(world, entity_type, entry, guids) do
    world
    |> guids.()
    |> Enum.filter(fn guid ->
      Guid.entity_type(guid) == entity_type and (is_nil(entry) or Guid.entry(guid) == entry)
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

  defp dispatch({:trigger_creature_spell, guid, spell_id}),
    do: Entity.trigger_spell(guid, spell_id, guid, triggered: true)

  defp summon(world, entry, position, despawn_delay_ms) do
    with %Mob{} = mob <-
           SummonLoader.build(entry, world, position, despawn_type: 3, despawn_delay_ms: despawn_delay_ms),
         {:ok, _pid} <- MobLoader.start_mob(mob) do
      :ok
    else
      _error -> :ok
    end
  end
end
