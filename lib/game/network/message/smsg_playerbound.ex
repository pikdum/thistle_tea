defmodule ThistleTea.Game.Network.Message.SmsgPlayerbound do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PLAYERBOUND

  defstruct [:guid, :area]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, area: area}), do: <<guid::little-size(64), area::little-size(32)>>
end
