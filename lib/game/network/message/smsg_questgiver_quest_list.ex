defmodule ThistleTea.Game.Network.Message.SmsgQuestgiverQuestList do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTGIVER_QUEST_LIST

  alias ThistleTea.Game.Entity.Data.Quest

  defstruct [:npc_guid, :entries, title: "", emote_delay: 0, emote: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.npc_guid::little-size(64)>> <>
      message.title <>
      <<0, message.emote_delay::little-size(32), message.emote::little-size(32), length(message.entries)::size(8)>> <>
      Enum.map_join(message.entries, fn {%Quest{} = quest, icon} ->
        <<quest.id::little-size(32), icon::little-size(32), quest.level::little-size(32)>> <>
          quest.title <> <<0>>
      end)
  end
end
