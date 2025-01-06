defmodule ThistleTea.Game.Chat.Emote do
  alias ThistleTea.Game.Chat
  import ThistleTea.Util, only: [unpack_guid: 1]

  @range 25

  @smsg_text_emote 0x105
  @smsg_emote 0x103

  @text_emote_agree 1
  @text_emote_applaud 5
  @text_emote_bow 17
  @text_emote_cheer 21
  @text_emote_chicken 22
  @text_emote_cry 31
  @text_emote_dance 34
  @text_emote_eat 37
  @text_emote_flex 41
  @text_emote_kiss 58
  @text_emote_kneel 59
  @text_emote_laugh 60
  @text_emote_no 66
  @text_emote_point 72
  @text_emote_roar 75
  @text_emote_rude 77
  @text_emote_salute 78
  @text_emote_shout 82
  @text_emote_shy 84
  @text_emote_sit 86
  @text_emote_sleep 87
  @text_emote_stand 141
  @text_emote_talk 93
  @text_emote_wave 101
  @text_emote_yes 273

  @emote_oneshot_talk 1
  @emote_oneshot_bow 2
  @emote_oneshot_wave 3
  @emote_oneshot_cheer 4
  @emote_oneshot_eat 7
  @emote_state_dance 10
  @emote_oneshot_laugh 11
  @emote_state_sleep 12
  @emote_state_sit 13
  @emote_oneshot_rude 14
  @emote_oneshot_roar 15
  @emote_oneshot_kneel 16
  @emote_oneshot_kiss 17
  @emote_oneshot_cry 18
  @emote_oneshot_chicken 19
  @emote_oneshot_applaud 21
  @emote_oneshot_shout 22
  @emote_oneshot_flex 23
  @emote_oneshot_shy 24
  @emote_oneshot_point 25
  @emote_state_stand 26
  @emote_oneshot_salute 66
  @emote_oneshot_yes 273
  @emote_oneshot_no 274

  def text_emote_to_emote do
    %{
      @text_emote_agree => @emote_oneshot_yes,
      @text_emote_applaud => @emote_oneshot_applaud,
      @text_emote_bow => @emote_oneshot_bow,
      @text_emote_cheer => @emote_oneshot_cheer,
      @text_emote_chicken => @emote_oneshot_chicken,
      @text_emote_cry => @emote_oneshot_cry,
      @text_emote_dance => @emote_state_dance,
      @text_emote_eat => @emote_oneshot_eat,
      @text_emote_flex => @emote_oneshot_flex,
      @text_emote_kiss => @emote_oneshot_kiss,
      @text_emote_kneel => @emote_oneshot_kneel,
      @text_emote_laugh => @emote_oneshot_laugh,
      @text_emote_no => @emote_oneshot_no,
      @text_emote_point => @emote_oneshot_point,
      @text_emote_roar => @emote_oneshot_roar,
      @text_emote_rude => @emote_oneshot_rude,
      @text_emote_salute => @emote_oneshot_salute,
      @text_emote_shout => @emote_oneshot_shout,
      @text_emote_shy => @emote_oneshot_shy,
      # TODO: /sit isn't working properly
      # might be conflicting with CMSG_STANDSTATECHANGE implementation?
      @text_emote_sit => @emote_state_sit,
      @text_emote_sleep => @emote_state_sleep,
      @text_emote_stand => @emote_state_stand,
      @text_emote_talk => @emote_oneshot_talk,
      @text_emote_wave => @emote_oneshot_wave,
      @text_emote_yes => @emote_oneshot_yes
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
    emote_id = text_emote_to_emote()[text_emote] || 0

    <<emote_id::little-size(32)>> <>
      <<sender_guid::little-size(64)>>
  end

  defp get_target_name(0) do
    ""
  end

  defp get_target_name(target_guid) do
    with pid <- :ets.lookup_element(:entities, target_guid, 2) do
      GenServer.call(pid, :get_name)
    end
  end

  def handle_packet(body, state) do
    <<text_emote::little-size(32), emote::little-size(32), target::little-size(64)>> = body

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
