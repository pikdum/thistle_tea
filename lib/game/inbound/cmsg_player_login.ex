defmodule ThistleTea.Game.Inbound.CmsgPlayerLogin do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PLAYER_LOGIN

  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Outbound

  require Logger

  defstruct [:character_guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<character_guid::little-size(64)>> = payload

    %__MODULE__{
      character_guid: character_guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{character_guid: character_guid}, %ConnectionState{account: account, player_pid: nil} = state)
      when not is_nil(account) do
    Logger.info("CMSG_PLAYER_LOGIN character_guid=#{character_guid}")

    case PlayerServer.login(account, self(), character_guid) do
      {:ok, player_pid} ->
        ConnectionState.attach_player(state, player_pid)

      {:error, reason} ->
        Logger.error("CMSG_PLAYER_LOGIN failed character_guid=#{character_guid} reason=#{inspect(reason)}")

        Outbound.send_packet(%Message.SmsgCharacterLoginFailed{
          result: Message.SmsgCharacterLoginFailed.result(:failed)
        })

        state
    end
  end

  def handle(%__MODULE__{}, state), do: state
end
