defmodule ThistleTea.Game.Inbound.CmsgAuthSession do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_AUTH_SESSION

  alias ThistleTea.Auth.Account
  alias ThistleTea.Auth.SessionKey
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.Sessions
  alias ThistleTea.Game.World.Outbound

  defstruct [
    :build,
    :server_id,
    :username,
    :client_seed,
    :client_proof
  ]

  @impl ClientMessage
  def from_binary(payload) do
    with <<build::little-size(32), server_id::little-size(32), rest::binary>> <- payload,
         {:ok, username, rest} <- BinaryUtils.parse_string(rest),
         <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> <-
           rest do
      %__MODULE__{
        build: build,
        server_id: server_id,
        username: username,
        client_seed: client_seed,
        client_proof: client_proof
      }
    end
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{conn: %Connection{} = conn} = state) do
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
end
