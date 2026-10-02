defmodule ThistleTea.Game.Inbound.CmsgPlayedTime do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_PLAYED_TIME, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Login

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Login.played_time(state)
end
