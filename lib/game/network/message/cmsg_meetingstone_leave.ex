defmodule ThistleTea.Game.Network.Message.CmsgMeetingstoneLeave do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MEETINGSTONE_LEAVE

  alias ThistleTea.Game.World.Entity.Player.MeetingStones

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: MeetingStones.request(state, :leave)
end
