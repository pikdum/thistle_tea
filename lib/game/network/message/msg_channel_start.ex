defmodule ThistleTea.Game.Network.Message.MsgChannelStart do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_CHANNEL_START

  defstruct spell_id: 0,
            duration_ms: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{spell_id: spell_id, duration_ms: duration_ms}) do
    <<spell_id::little-size(32), duration_ms::little-size(32)>>
  end
end
