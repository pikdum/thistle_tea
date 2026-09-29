defmodule ThistleTea.Game.Network.Message.CmsgMeetingstoneLeave do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MEETINGSTONE_LEAVE

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
