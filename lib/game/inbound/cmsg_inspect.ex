defmodule ThistleTea.Game.Inbound.CmsgInspect do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_INSPECT

  alias ThistleTea.Game.World.Entity.Player.Inspection

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Inspection.inspect(state, guid)
end
