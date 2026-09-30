defmodule ThistleTea.Game.Inbound.CmsgGroupInvite do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GROUP_INVITE

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct [:name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Groups.invite(state, name)
end
