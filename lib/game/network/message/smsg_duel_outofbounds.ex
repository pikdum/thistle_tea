defmodule ThistleTea.Game.Network.Message.SmsgDuelOutofbounds do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DUEL_OUTOFBOUNDS

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
