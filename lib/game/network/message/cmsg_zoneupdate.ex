defmodule ThistleTea.Game.Network.Message.CmsgZoneupdate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ZONEUPDATE

  defstruct [:area]

  @impl ClientMessage
  def from_binary(payload) do
    case payload do
      <<area::little-size(32)>> -> %__MODULE__{area: area}
      _ -> %__MODULE__{}
    end
  end
end
