defmodule ThistleTea.Game.Inbound.CmsgSetActiveMover do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_SET_ACTIVE_MOVER, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Mover

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>) do
    %__MODULE__{guid: guid}
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Mover.select(state, guid)
end
