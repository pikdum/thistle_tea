defmodule ThistleTea.Game.Inbound.CmsgZoneupdate do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_ZONEUPDATE

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Zone

  defstruct [:area]

  @impl ClientMessage
  def from_binary(payload) do
    case payload do
      <<area::little-size(32)>> -> %__MODULE__{area: area}
      _ -> %__MODULE__{}
    end
  end

  @impl ClientMessage
  def handle(%__MODULE__{area: client_zone}, %{ready: true, character: %Character{}} = state),
    do: Zone.update(state, client_zone)

  def handle(%__MODULE__{}, state), do: state
end
