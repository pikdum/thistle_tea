defmodule ThistleTea.Game.Network.Message.MsgRaidReadyCheckResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_RAID_READY_CHECK

  defstruct [:guid, :ready?]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: nil}), do: <<>>
  def to_binary(%__MODULE__{guid: guid, ready?: ready?}), do: <<guid::little-size(64), if(ready?, do: 1, else: 0)>>
end
