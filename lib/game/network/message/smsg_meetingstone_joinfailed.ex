defmodule ThistleTea.Game.Network.Message.SmsgMeetingstoneJoinfailed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MEETINGSTONE_JOINFAILED

  defstruct [:reason]

  @impl ServerMessage
  def to_binary(%__MODULE__{reason: reason}), do: <<reason::little-size(8)>>
end
