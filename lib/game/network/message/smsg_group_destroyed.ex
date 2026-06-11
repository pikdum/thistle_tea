defmodule ThistleTea.Game.Network.Message.SmsgGroupDestroyed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GROUP_DESTROYED

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}) do
    <<>>
  end
end
