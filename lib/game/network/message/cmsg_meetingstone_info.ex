defmodule ThistleTea.Game.Network.Message.CmsgMeetingstoneInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MEETINGSTONE_INFO

  alias ThistleTea.Game.Player.MeetingStones

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: MeetingStones.request(state, :info)
end
