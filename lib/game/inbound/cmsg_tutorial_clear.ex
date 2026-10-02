defmodule ThistleTea.Game.Inbound.CmsgTutorialClear do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_TUTORIAL_CLEAR, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Login

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Login.set_tutorials(state, :clear)
end
