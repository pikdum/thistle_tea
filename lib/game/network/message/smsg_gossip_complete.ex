defmodule ThistleTea.Game.Network.Message.SmsgGossipComplete do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GOSSIP_COMPLETE

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
