defmodule ThistleTea.Game.Network.Message.SmsgGroupDecline do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GROUP_DECLINE

  defstruct [:name]

  @impl ServerMessage
  def to_binary(%__MODULE__{name: name}) do
    name <> <<0>>
  end
end
