defmodule ThistleTea.Game.Network.Message.CmsgQueryTime do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUERY_TIME

  alias ThistleTea.Game.Player.Login

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Login.query_time(state)
end
