defmodule ThistleTea.Game.Network.Message.CmsgTaxiqueryavailablenodes do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TAXIQUERYAVAILABLENODES

  alias ThistleTea.Game.Player.Taxi

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Taxi.query(state, guid)
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
