defmodule ThistleTea.Game.Network.Message.CmsgAreaSpiritHealerQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AREA_SPIRIT_HEALER_QUERY

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Battlegrounds.spirit_healer_time(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
