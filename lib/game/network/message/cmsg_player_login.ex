defmodule ThistleTea.Game.Network.Message.CmsgPlayerLogin do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PLAYER_LOGIN

  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Network.ConnectionState

  defstruct [:character_guid]

  @impl ClientMessage
  def handle(%__MODULE__{character_guid: character_guid}, %ConnectionState{account: account, player_pid: nil} = state)
      when not is_nil(account) do
    case PlayerServer.login(account, self(), character_guid) do
      {:ok, player_pid} ->
        ConnectionState.attach_player(state, player_pid)

      {:error, _reason} ->
        state
    end
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<character_guid::little-size(64)>> = payload

    %__MODULE__{
      character_guid: character_guid
    }
  end
end
