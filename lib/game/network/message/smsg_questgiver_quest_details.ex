defmodule ThistleTea.Game.Network.Message.SmsgQuestgiverQuestDetails do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTGIVER_QUEST_DETAILS

  import Bitwise

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @hidden_rewards_flag 0x200

  defstruct [:npc_guid, :quest, activate_accept: true]

  @impl ServerMessage
  def to_binary(%__MODULE__{npc_guid: npc_guid, quest: %Quest{} = q} = message) do
    <<npc_guid::little-size(64), q.id::little-size(32)>> <>
      q.title <>
      <<0>> <>
      q.details <>
      <<0>> <>
      q.objectives_text <>
      <<0, activate_accept(message)::little-size(32)>> <>
      rewards_binary(q) <>
      <<q.reward_spell::little-size(32)>> <>
      emotes_binary(q)
  end

  defp activate_accept(%__MODULE__{activate_accept: true}), do: 1
  defp activate_accept(%__MODULE__{}), do: 0

  defp rewards_binary(%Quest{flags: flags}) when (flags &&& @hidden_rewards_flag) != 0 do
    <<0::little-size(32), 0::little-size(32), 0::little-size(32)>>
  end

  defp rewards_binary(%Quest{} = q) do
    item_list_binary(q.reward_choice_items) <>
      item_list_binary(q.reward_items) <>
      <<q.reward_money::little-signed-size(32)>>
  end

  defp item_list_binary(id_counts) do
    <<length(id_counts)::little-size(32)>> <>
      Enum.map_join(id_counts, fn {item_id, count} ->
        <<item_id::little-size(32), count::little-size(32), display_id(item_id)::little-size(32)>>
      end)
  end

  defp emotes_binary(%Quest{details_emotes: details_emotes}) do
    emotes =
      details_emotes
      |> Enum.reverse()
      |> Enum.drop_while(fn {emote, _delay} -> emote == 0 end)
      |> Enum.reverse()

    <<length(emotes)::little-size(32)>> <>
      Enum.map_join(emotes, fn {emote, delay} ->
        <<emote::little-size(32), delay::little-size(32)>>
      end)
  end

  defp display_id(item_id) do
    case ItemLoader.get_template(item_id) do
      %ItemTemplate{display_id: display_id} -> display_id
      _template -> 0
    end
  end
end
