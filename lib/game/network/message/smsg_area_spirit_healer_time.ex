defmodule ThistleTea.Game.Network.Message.SmsgAreaSpiritHealerTime do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AREA_SPIRIT_HEALER_TIME

  defstruct [:guid, :time_ms]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.guid::little-size(64), message.time_ms::little-size(32)>>
  end
end
