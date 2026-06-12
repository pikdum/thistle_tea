defmodule ThistleTea.Game.Network.Message.CmsgPlayerLogin do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PLAYER_LOGIN

  alias ThistleTea.Game.Player.Login

  defstruct [:character_guid]

  @impl ClientMessage
  def handle(%__MODULE__{character_guid: character_guid}, state) do
    Login.enter_world(state, character_guid)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<character_guid::little-size(64)>> = payload

    %__MODULE__{
      character_guid: character_guid
    }
  end
end
