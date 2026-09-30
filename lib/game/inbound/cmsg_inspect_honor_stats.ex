defmodule ThistleTea.Game.Inbound.CmsgInspectHonorStats do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_INSPECT_HONOR_STATS

  alias ThistleTea.Game.World.Entity.Player.Honor

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Honor.inspect(state, guid)
end
