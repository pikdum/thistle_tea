defmodule ThistleTea.Game.Network.Message.CmsgResurrectResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_RESURRECT_RESPONSE

  defstruct [:guid, :status]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), status::little-size(8), _rest::binary>>) do
    %__MODULE__{guid: guid, status: status}
  end
end
