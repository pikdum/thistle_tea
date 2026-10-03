defmodule ThistleTea.Game.Network.Message.SmsgZoneUnderAttack do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ZONE_UNDER_ATTACK

  defstruct [:area_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{area_id: area_id}), do: <<area_id::little-size(32)>>
end
