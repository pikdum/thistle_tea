defmodule ThistleTea.Game.Network.Message.SmsgMeetingstoneInProgress do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MEETINGSTONE_IN_PROGRESS

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
