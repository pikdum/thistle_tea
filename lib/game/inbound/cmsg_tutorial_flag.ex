defmodule ThistleTea.Game.Inbound.CmsgTutorialFlag do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_TUTORIAL_FLAG, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Login

  defstruct [:index]

  @impl ClientMessage
  def from_binary(<<index::little-size(32)>>), do: %__MODULE__{index: index}

  @impl ClientMessage
  def handle(%__MODULE__{index: index}, state), do: Login.mark_tutorial(state, index)
end
