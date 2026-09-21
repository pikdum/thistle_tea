defmodule ThistleTea.Game.Network.Message.CmsgGroupInvite do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_INVITE

  alias ThistleTea.Game.Player.Groups

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Groups.invite(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end
