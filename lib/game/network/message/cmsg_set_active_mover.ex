defmodule ThistleTea.Game.Network.Message.CmsgSetActiveMover do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_ACTIVE_MOVER

  alias ThistleTea.Game.Player.Mover

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Mover.select(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>) do
    %__MODULE__{guid: guid}
  end
end
