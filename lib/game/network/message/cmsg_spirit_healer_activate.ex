defmodule ThistleTea.Game.Network.Message.CmsgSpiritHealerActivate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SPIRIT_HEALER_ACTIVATE

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
