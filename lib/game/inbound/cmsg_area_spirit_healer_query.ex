defmodule ThistleTea.Game.Inbound.CmsgAreaSpiritHealerQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_AREA_SPIRIT_HEALER_QUERY

  alias ThistleTea.Game.World.Entity.Player.Battlegrounds

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Battlegrounds.spirit_healer_time(state, guid)
end
