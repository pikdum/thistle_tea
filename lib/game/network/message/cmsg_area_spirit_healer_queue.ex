defmodule ThistleTea.Game.Network.Message.CmsgAreaSpiritHealerQueue do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AREA_SPIRIT_HEALER_QUEUE

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Battlegrounds.queue_resurrection(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
