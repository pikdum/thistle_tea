defmodule ThistleTea.Game.Network.Message.CmsgGuildAddRank do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_ADD_RANK

  defstruct [:name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end
