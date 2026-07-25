defmodule ThistleTea.Game.Entity.EventSink.ClientProjection do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader

  @listen_range_say 25.0
  @listen_range_yell 300.0

  def emit(%Character{} = entity, %Effects.ConsumeCastItem{cast_item_guid: item_guid}) when is_integer(item_guid) do
    send(self(), {:consume_cast_item, item_guid})
    entity
  end

  def emit(entity, %Effects.ConsumeCastItem{}), do: entity

  def emit(%Character{} = entity, %Effects.FeedPet{} = effect) do
    send(self(), {:feed_pet, effect.cast_item_guid, effect.target_guid, effect.spell_id, effect.range_yards})
    entity
  end

  def emit(entity, %Effects.FeedPet{}), do: entity

  def emit(%Character{} = entity, %Effects.EnchantItem{} = effect) do
    duration_ms = ItemEnchantmentLoader.duration_ms(effect.spell.id, effect.effect)
    send(self(), {:enchant_item, effect.target_guid, effect.spell, effect.effect.misc_value, duration_ms})
    entity
  end

  def emit(entity, %Effects.EnchantItem{}), do: entity

  def emit(%Character{} = entity, %Effects.OpenGameObject{target_guid: object_guid}) when is_integer(object_guid) do
    send(self(), {:open_gameobject_loot, object_guid})
    entity
  end

  def emit(entity, %Effects.OpenGameObject{}), do: entity

  def emit(entity, %Effects.GiveItem{target_guid: target_guid, item_id: item_id, count: count})
      when is_integer(target_guid) do
    case Entity.pid(target_guid) do
      pid when is_pid(pid) -> send(pid, {:create_item, item_id, count})
      _pid -> :ok
    end

    entity
  end

  def emit(%Character{} = entity, %Effects.CreateItem{item_id: item_id, count: count}) do
    send(self(), {:create_item, item_id, count})
    entity
  end

  def emit(entity, %Effects.CreateItem{}), do: entity

  def emit(%Character{} = entity, %Effects.ConsumeReagents{reagents: reagents}) when is_list(reagents) do
    send(self(), {:consume_reagents, reagents})
    entity
  end

  def emit(entity, %Effects.ConsumeReagents{}), do: entity

  def emit(%{object: %{guid: guid}, internal: %Internal{name: name}} = entity, %Effects.MonsterTalk{} = effect) do
    effect.chat_type
    |> monster_chat_type()
    |> Message.SmsgMessagechat.monster(effect.text, guid, name, effect.target_guid)
    |> World.broadcast_packet(entity, range: listen_range(effect.chat_type))

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.Emote{emote_id: emote_id}) do
    %Message.SmsgEmote{emote: emote_id, guid: guid}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.ScriptSteps{} = effect) do
    Process.send_after(self(), {:ai_script_steps, effect.steps, effect.target_guid}, effect.duration_ms || 0)
    entity
  end

  def emit(entity, %Effects.ForwardScriptSteps{} = effect) do
    case Entity.pid(effect.target_guid) do
      pid when is_pid(pid) -> send(pid, {:ai_script_steps, effect.steps, effect.source_guid})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.PlaySound{sound_id: sound_id}) do
    %Message.SmsgPlaySound{sound_id: sound_id}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.PlayObjectSound{sound_id: sound_id}) do
    %Message.SmsgPlayObjectSound{sound_id: sound_id, guid: guid}
    |> World.broadcast_packet(entity)

    entity
  end

  defp monster_chat_type(chat_type) when chat_type in [:yell, :zone_yell], do: :monster_yell
  defp monster_chat_type(chat_type) when chat_type in [:text_emote, :boss_emote, :zone_emote], do: :monster_emote
  defp monster_chat_type(_chat_type), do: :monster_say

  defp listen_range(chat_type) when chat_type in [:yell, :zone_yell], do: @listen_range_yell
  defp listen_range(_chat_type), do: @listen_range_say
end
