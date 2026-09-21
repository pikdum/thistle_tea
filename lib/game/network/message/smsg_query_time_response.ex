defmodule ThistleTea.Game.Network.Message.SmsgQueryTimeResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUERY_TIME_RESPONSE

  defstruct [:time]

  @impl ServerMessage
  def to_binary(%__MODULE__{time: time}), do: <<time::little-size(32)>>
end
