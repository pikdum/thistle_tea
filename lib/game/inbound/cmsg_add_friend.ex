defmodule ThistleTea.Game.Inbound.CmsgAddFriend do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_ADD_FRIEND

  alias ThistleTea.Game.World.Entity.Player.Social

  defstruct [:name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Social.add(state, :friend, name)
end
