defmodule ThistleTea.Game.Inbound.CmsgMeetingstoneInfo do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_MEETINGSTONE_INFO

  alias ThistleTea.Game.World.Entity.Player.MeetingStones

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: MeetingStones.request(state, :info)
end
