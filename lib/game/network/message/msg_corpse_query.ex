defmodule ThistleTea.Game.Network.Message.MsgCorpseQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_CORPSE_QUERY

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
