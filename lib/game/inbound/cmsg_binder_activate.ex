defmodule ThistleTea.Game.Inbound.CmsgBinderActivate do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_BINDER_ACTIVATE

  alias ThistleTea.Game.World.Entity.Player.HomeBind

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: HomeBind.activate(state, guid)
end
