defmodule ThistleTea.Game.Network.Message.CmsgTaxinodeStatusQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TAXINODE_STATUS_QUERY

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
