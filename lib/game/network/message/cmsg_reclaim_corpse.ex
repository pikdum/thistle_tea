defmodule ThistleTea.Game.Network.Message.CmsgReclaimCorpse do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_RECLAIM_CORPSE

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
