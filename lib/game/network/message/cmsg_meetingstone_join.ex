defmodule ThistleTea.Game.Network.Message.CmsgMeetingstoneJoin do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MEETINGSTONE_JOIN

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
