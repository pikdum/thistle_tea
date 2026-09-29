defmodule ThistleTea.Game.Network.Message.CmsgAreaSpiritHealerQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AREA_SPIRIT_HEALER_QUERY

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
