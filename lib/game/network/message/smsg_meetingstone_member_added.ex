defmodule ThistleTea.Game.Network.Message.SmsgMeetingstoneMemberAdded do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MEETINGSTONE_MEMBER_ADDED

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}), do: <<guid::little-size(64)>>
end
