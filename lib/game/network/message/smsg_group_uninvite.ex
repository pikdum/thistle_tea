defmodule ThistleTea.Game.Network.Message.SmsgGroupUninvite do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GROUP_UNINVITE

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}) do
    <<>>
  end
end
