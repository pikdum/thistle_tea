defmodule ThistleTea.Game.Network.Message.CmsgPvpLogData do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_PVP_LOG_DATA

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
