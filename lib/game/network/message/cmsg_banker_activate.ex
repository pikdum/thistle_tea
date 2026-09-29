defmodule ThistleTea.Game.Network.Message.CmsgBankerActivate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BANKER_ACTIVATE

  defstruct [:banker_guid]

  @impl ClientMessage
  def from_binary(<<banker_guid::little-size(64)>>), do: %__MODULE__{banker_guid: banker_guid}
end
