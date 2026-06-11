defmodule ThistleTea.Game.Network.Message.MsgChannelUpdate do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_CHANNEL_UPDATE

  defstruct time_ms: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{time_ms: time_ms}) do
    <<time_ms::little-size(32)>>
  end
end
