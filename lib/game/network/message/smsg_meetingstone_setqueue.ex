defmodule ThistleTea.Game.Network.Message.SmsgMeetingstoneSetqueue do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MEETINGSTONE_SETQUEUE

  defstruct area: 0, status: 5

  @impl ServerMessage
  def to_binary(%__MODULE__{area: area, status: status}), do: <<area::little-size(32), status::little-size(8)>>
end
