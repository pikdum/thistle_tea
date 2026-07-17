defmodule ThistleTea.Game.Network.Message.SmsgSummonRequest do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SUMMON_REQUEST

  defstruct [:summoner_guid, :zone_id, :auto_decline_ms]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.summoner_guid::little-size(64), message.zone_id::little-size(32),
      message.auto_decline_ms::little-size(32)>>
  end
end
