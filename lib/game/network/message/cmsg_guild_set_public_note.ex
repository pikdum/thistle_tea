defmodule ThistleTea.Game.Network.Message.CmsgGuildSetPublicNote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_SET_PUBLIC_NOTE

  defstruct [:name, :note]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, rest} = BinaryUtils.parse_string(payload)
    {:ok, note, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{name: name, note: note}
  end
end
