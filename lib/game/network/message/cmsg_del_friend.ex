defmodule ThistleTea.Game.Network.Message.CmsgDelFriend do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_DEL_FRIEND

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{guid: guid}
end
