defmodule ThistleTea.Game.Network.Message.CmsgTaxiqueryavailablenodes do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TAXIQUERYAVAILABLENODES

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
