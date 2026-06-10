defmodule ThistleTea.Game.Network.Message.SmsgQuestgiverOfferReward do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTGIVER_OFFER_REWARD

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  defstruct [:npc_guid, :quest, enable_next: true]

  @impl ServerMessage
  def to_binary(%__MODULE__{npc_guid: npc_guid, quest: %Quest{} = q} = message) do
    <<npc_guid::little-size(64), q.id::little-size(32)>> <>
      q.title <>
      <<0>> <>
      q.offer_reward_text <>
      <<0, enable_next(message)::little-size(32)>> <>
      emotes_binary(q) <>
      item_list_binary(q.reward_choice_items) <>
      item_list_binary(q.reward_items) <>
      <<q.reward_money::little-signed-size(32), 0::little-size(32), q.reward_spell::little-size(32)>>
  end

  defp enable_next(%__MODULE__{enable_next: true}), do: 1
  defp enable_next(%__MODULE__{}), do: 0

  defp emotes_binary(%Quest{offer_reward_emotes: offer_reward_emotes}) do
    emotes = Enum.take_while(offer_reward_emotes, fn {emote, _delay} -> emote > 0 end)

    <<length(emotes)::little-size(32)>> <>
      Enum.map_join(emotes, fn {emote, delay} ->
        <<delay::little-size(32), emote::little-size(32)>>
      end)
  end

  defp item_list_binary(id_counts) do
    <<length(id_counts)::little-size(32)>> <>
      Enum.map_join(id_counts, fn {item_id, count} ->
        <<item_id::little-size(32), count::little-size(32), display_id(item_id)::little-size(32)>>
      end)
  end

  defp display_id(item_id) do
    case ItemLoader.get_template(item_id) do
      %ItemTemplate{display_id: display_id} -> display_id
      _template -> 0
    end
  end
end
