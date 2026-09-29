defmodule ThistleTea.Game.Network.Message.CmsgMeetingstoneJoin do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MEETINGSTONE_JOIN

  alias ThistleTea.Game.World.Entity.Player.MeetingStones

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: MeetingStones.join(state, guid)
end
