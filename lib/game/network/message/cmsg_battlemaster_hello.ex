defmodule ThistleTea.Game.Network.Message.CmsgBattlemasterHello do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BATTLEMASTER_HELLO

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
