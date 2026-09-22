defmodule ThistleTea.Game.Network.Message.SmsgAttackswingNotinrange do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ATTACKSWING_NOTINRANGE

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
