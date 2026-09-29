defmodule ThistleTea.Game.Network.Message.CmsgGuildInfoText do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_INFO_TEXT

  defstruct [:info]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, info, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{info: info}
  end
end
