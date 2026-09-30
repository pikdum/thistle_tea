defmodule ThistleTea.Game.Inbound.CmsgReclaimCorpse do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_RECLAIM_CORPSE

  alias ThistleTea.Game.World.Entity.Player.Corpses

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Corpses.reclaim(state)
end
