defmodule ThistleTea.Game.Chat.Emote do
  alias ThistleTea.Game.Chat
  import ThistleTea.Util, only: [unpack_guid: 1]

  @range 25

  @smsg_text_emote 0x105
  @smsg_emote 0x103

  @text_emote_dance 34
  @emote_dance 10

  defp text_emote_to_emote do
    %{
      @text_emote_dance => @emote_dance
    }
  end

  defp text_emote_packet(sender_guid, text_emote, emote_num, target_name) do
    target_name_length = String.length(target_name) + 1

    <<sender_guid::little-size(64)>> <>
      <<text_emote::little-size(32)>> <>
      <<emote_num::little-size(32)>> <>
      <<target_name_length::little-size(32)>> <> target_name <> <<0>>
  end

  defp emote_packet(sender_guid, text_emote) do
    emote_id = text_emote_to_emote()[text_emote]

    <<emote_id::little-size(32)>> <>
      <<sender_guid::little-size(64)>>
  end

  defp get_target_name(0) do
    ""
  end

  defp get_target_name(target_guid) do
    # TODO: Allow for targets to be mobs, not just players
    case :ets.lookup(:guid_name, target_guid) do
      [{^target_guid, character_name, _, _, _, _}] ->
        character_name
      [] -> ""
    end
  end

  def handle_packet(body, state) do
    <<text_emote::little-size(32), emote::little-size(32), rest::binary>> = body

    {target, _} = unpack_guid(rest)
    target_name = get_target_name(target)

    text_emote_p = text_emote_packet(state.guid, text_emote, emote, target_name)
    emote_p = emote_packet(state.guid, text_emote)

    pids_in_range = Chat.get_player_pids_in_chat_range(state, @range)

    for pid <- pids_in_range do
      GenServer.cast(pid, {:send_packet, @smsg_emote, emote_p})
      GenServer.cast(pid, {:send_packet, @smsg_text_emote, text_emote_p})
    end
  end
end
