defmodule ThistleTea.Game.Inbound.CmsgQueryTime do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_QUERY_TIME, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Login

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Login.query_time(state)
end
