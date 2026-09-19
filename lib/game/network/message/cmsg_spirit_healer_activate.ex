defmodule ThistleTea.Game.Network.Message.CmsgSpiritHealerActivate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SPIRIT_HEALER_ACTIVATE

  alias ThistleTea.Game.Player.SpiritHealer

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: SpiritHealer.activate(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
