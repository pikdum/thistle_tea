defmodule ThistleTea.Game.Entity.EventSink.ClientProjection do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader

  @listen_range_say 25.0
  @listen_range_yell 300.0

  def emit(%Character{} = entity, %Effects.CancelAutoRepeat{}, context) do
    Context.send_packet(context, %Message.SmsgCancelAutoRepeat{})
    entity
  end

  def emit(entity, %Effects.CancelAutoRepeat{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.ConsumeCastItem{cast_item_guid: item_guid}, context)
      when is_integer(item_guid) do
    Context.send(context, {:consume_cast_item, item_guid})
    entity
  end

  def emit(entity, %Effects.ConsumeCastItem{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.FeedPet{} = effect, context) do
    Context.send(context, {:feed_pet, effect.cast_item_guid, effect.target_guid, effect.spell_id, effect.range_yards})
    entity
  end

  def emit(entity, %Effects.FeedPet{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.EnchantItem{} = effect, context) do
    duration_ms = ItemEnchantmentLoader.duration_ms(effect.spell.id, effect.effect)
    Context.send(context, {:enchant_item, effect.target_guid, effect.spell, effect.effect.misc_value, duration_ms})
    entity
  end

  def emit(entity, %Effects.EnchantItem{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.OpenGameObject{target_guid: object_guid}, context)
      when is_integer(object_guid) do
    Context.send(context, {:open_gameobject_loot, object_guid})
    entity
  end

  def emit(entity, %Effects.OpenGameObject{}, _context), do: entity

  def emit(entity, %Effects.GiveItem{target_guid: target_guid, item_id: item_id, count: count}, _context)
      when is_integer(target_guid) do
    case Entity.pid(target_guid) do
      pid when is_pid(pid) -> send(pid, {:create_item, item_id, count})
      _pid -> :ok
    end

    entity
  end

  def emit(%Character{} = entity, %Effects.CreateItem{item_id: item_id, count: count}, context) do
    Context.send(context, {:create_item, item_id, count})
    entity
  end

  def emit(entity, %Effects.CreateItem{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.ConsumeReagents{reagents: reagents}, context) when is_list(reagents) do
    Context.send(context, {:consume_reagents, reagents})
    entity
  end

  def emit(entity, %Effects.ConsumeReagents{}, _context), do: entity

  def emit(
        %{object: %{guid: guid}, internal: %Internal{name: name}} = entity,
        %Effects.MonsterTalk{} = effect,
        _context
      ) do
    effect.chat_type
    |> monster_chat_type()
    |> Message.SmsgMessagechat.monster(effect.text, guid, name, effect.target_guid)
    |> World.broadcast_packet(entity, range: listen_range(effect.chat_type))

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.Emote{emote_id: emote_id}, _context) do
    %Message.SmsgEmote{emote: emote_id, guid: guid}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.GameObjectCustomAnimation{animation: animation}, _context) do
    %Message.SmsgGameobjectCustomAnim{guid: guid, animation: animation}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.ScriptSteps{} = effect, context) do
    Context.send_after(context, {:ai_script_steps, effect.steps, effect.target_guid}, effect.duration_ms || 0)
    entity
  end

  def emit(entity, %Effects.ForwardScriptSteps{} = effect, _context) do
    Entity.start_script(effect.target_guid, effect.steps, effect.source_guid)
    entity
  end

  def emit(entity, %Effects.SendTaxiPath{} = effect, _context) do
    case Entity.pid(effect.target_guid) do
      pid when is_pid(pid) -> send(pid, {:send_taxi_path, effect.path_id})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.PlaySound{sound_id: sound_id}, _context) do
    %Message.SmsgPlaySound{sound_id: sound_id}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.PlayObjectSound{sound_id: sound_id}, _context) do
    %Message.SmsgPlayObjectSound{sound_id: sound_id, guid: guid}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.ForcedReactionsChanged{} = effect, context) do
    Context.send_packet(context, %Message.SmsgSetForcedReactions{reactions: effect.reactions})

    if effect.friendly_faction_ids != [] do
      Context.send(context, {:stop_attack_factions, effect.friendly_faction_ids})
    end

    entity
  end

  def emit(entity, %Effects.ForcedReactionsChanged{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.FactionAtWarChanged{} = effect, context) do
    Context.send_packet(context, %Message.SmsgSetFactionAtwar{
      index: effect.index,
      enabled: effect.enabled
    })

    entity
  end

  def emit(entity, %Effects.FactionAtWarChanged{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.ReputationChange{} = effect, context) do
    Context.send(context, {:reputation_change, effect.faction_id, effect.value})
    entity
  end

  def emit(entity, %Effects.ReputationChange{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.QuestCastCredit{} = effect, context) do
    Context.send(context, {:quest_cast_credit, effect.target_guids, effect.spell_id})
    entity
  end

  def emit(entity, %Effects.QuestCastCredit{}, _context), do: entity

  def emit(entity, %Effects.QuestEventCredit{} = effect, _context) do
    case Entity.pid(effect.player_guid) do
      pid when is_pid(pid) ->
        send(
          pid,
          {:quest_event_credit, effect.quest_id, effect.group?, effect.distance, effect.world_object_guid}
        )

      _pid ->
        :ok
    end

    entity
  end

  def emit(entity, %Effects.QuestFail{} = effect, _context) do
    case Entity.pid(effect.player_guid) do
      pid when is_pid(pid) -> send(pid, {:quest_fail, effect.quest_id, effect.group?})
      _pid -> :ok
    end

    entity
  end

  def emit(entity, %Effects.QuestInteractionCredit{} = effect, _context) do
    case Entity.pid(effect.player_guid) do
      pid when is_pid(pid) -> send(pid, {:quest_interaction_credit, effect.target_guid})
      _pid -> :ok
    end

    entity
  end

  def emit(entity, %Effects.QuestKillCredit{} = effect, _context) do
    case Entity.pid(effect.player_guid) do
      pid when is_pid(pid) ->
        send(pid, {:quest_kill_credit, effect.creature_entry, effect.group?})

      _pid ->
        :ok
    end

    entity
  end

  defp monster_chat_type(chat_type) when chat_type in [:yell, :zone_yell], do: :monster_yell
  defp monster_chat_type(chat_type) when chat_type in [:text_emote, :boss_emote, :zone_emote], do: :monster_emote
  defp monster_chat_type(_chat_type), do: :monster_say

  defp listen_range(chat_type) when chat_type in [:yell, :zone_yell], do: @listen_range_yell
  defp listen_range(_chat_type), do: @listen_range_say
end
