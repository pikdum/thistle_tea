defmodule ThistleTea.Game.Inbound.CmsgTaxiqueryavailablenodes do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_TAXIQUERYAVAILABLENODES

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Taxi

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Taxi.query(state, guid)
  end

  def handle(%__MODULE__{}, state), do: state
end
