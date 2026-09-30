defmodule ThistleTea.Game.Inbound.CmsgLootRelease do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LOOT_RELEASE

  alias ThistleTea.Game.World.Entity.Player.Looting
  alias ThistleTea.Game.World.Outbound

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true} = state), do: Looting.release(state)

  def handle(%__MODULE__{guid: guid}, state) do
    Outbound.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
    state
  end
end
