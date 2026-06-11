defmodule ThistleTea.Game.Network.Message.SmsgQuestupdateAddKill do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTUPDATE_ADD_KILL

  defstruct [:quest_id, :creature_entry, :count, :required, :victim_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<
      message.quest_id::little-size(32),
      message.creature_entry::little-size(32),
      message.count::little-size(32),
      message.required::little-size(32),
      message.victim_guid::little-size(64)
    >>
  end
end
