defmodule ThistleTea.Game.Network.Message.SmsgDuelInbounds do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DUEL_INBOUNDS

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
