defmodule ThistleTea.Game.Network.Message.SmsgQuestConfirmAccept do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUEST_CONFIRM_ACCEPT

  defstruct [:quest_id, :title, :sharer_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{quest_id: quest_id, title: title, sharer_guid: guid}) do
    <<quest_id::little-size(32), title::binary, 0, guid::little-size(64)>>
  end
end
