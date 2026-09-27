defmodule ThistleTea.Game.Network.Message.SmsgMeetingstoneComplete do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MEETINGSTONE_COMPLETE

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
