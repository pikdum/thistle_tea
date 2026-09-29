defmodule ThistleTea.Game.World.Inbound.Session do
  @moduledoc "Handles decoded authentication, character screen, login, and logout client messages."

  alias ThistleTea.Auth.Account
  alias ThistleTea.Auth.SessionKey
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Sessions
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.Characters
  alias ThistleTea.Game.World.Entity.Player.Logout
  alias ThistleTea.Game.World.Loader.Character, as: CharacterLoader
  alias ThistleTea.Game.World.Outbound

  require Logger

  def messages do
    [
      Message.CmsgAuthSession,
      Message.CmsgCharCreate,
      Message.CmsgCharEnum,
      Message.CmsgLogoutCancel,
      Message.CmsgLogoutRequest,
      Message.CmsgPing,
      Message.CmsgPlayerLogin
    ]
  end

  def handle(%Message.CmsgAuthSession{} = message, %{conn: %Connection{} = conn} = state) do
    case SessionKey.verify_world_proof(message.username, message.client_seed, conn.seed, message.client_proof) do
      {:ok, session_key} ->
        {:ok, account} = Account.get_user(message.username)
        :ok = Sessions.authenticate(account.id)
        Outbound.send_packet(Message.SmsgAuthResponse.ok())
        %{state | conn: %{conn | session_key: session_key}, account: account}

      :error ->
        Outbound.send_packet(Message.SmsgAuthResponse.failed())
        state
    end
  end

  def handle(%Message.CmsgCharCreate{} = message, state) do
    Logger.info("CMSG_CHAR_CREATE: #{message.name}")

    character = CharacterLoader.build(message, state.account.id)

    case Characters.create(character) do
      {:error, :character_exists} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x31})

      {:error, :character_limit} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x35})

      {:ok, _} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x2E})
    end

    state
  end

  def handle(%Message.CmsgCharEnum{}, state) do
    Logger.info("CMSG_CHAR_ENUM")

    state.account.id
    |> Characters.enum()
    |> Outbound.send_packet()

    state
  end

  def handle(%Message.CmsgLogoutCancel{}, state) do
    Logger.info("CMSG_LOGOUT_CANCEL")

    Logout.cancel(state)
  end

  def handle(%Message.CmsgLogoutRequest{}, state) do
    Logger.info("CMSG_LOGOUT_REQUEST")
    Logout.request(state)
  end

  def handle(%Message.CmsgPing{sequence_id: sequence_id, latency: latency}, %ConnectionState{} = state) do
    Logger.info("CMSG_PING: #{latency}")

    Outbound.send_packet(%Message.SmsgPong{sequence_id: sequence_id})
    %{state | latency: latency}
  end

  def handle(
        %Message.CmsgPlayerLogin{character_guid: character_guid},
        %ConnectionState{account: account, player_pid: nil} = state
      )
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

  def handle(%Message.CmsgPlayerLogin{}, state), do: state
end
