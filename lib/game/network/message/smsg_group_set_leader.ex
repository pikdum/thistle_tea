defmodule ThistleTea.Game.Network.Message.SmsgGroupSetLeader do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GROUP_SET_LEADER

  defstruct [:name]

  @impl ServerMessage
  def to_binary(%__MODULE__{name: name}) do
    name <> <<0>>
  end
end
