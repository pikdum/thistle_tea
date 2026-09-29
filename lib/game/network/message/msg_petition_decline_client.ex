defmodule ThistleTea.Game.Network.Message.MsgPetitionDeclineClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_PETITION_DECLINE

  alias ThistleTea.Game.Player.Petitions

  defstruct [:item_guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid}, state), do: Petitions.decline(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{item_guid: guid}
end
