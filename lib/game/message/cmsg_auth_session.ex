defmodule ThistleTea.Game.Message.CmsgAuthSession do
  alias ThistleTea.Game.Connection
  alias ThistleTea.Game.Handler
  alias ThistleTea.Game.Message
  alias ThistleTea.Util

  defstruct [
    :build,
    :server_id,
    :username,
    :client_seed,
    :client_proof
  ]

  defimpl Handler do
    def handle(message, state), do: Message.CmsgAuthSession.handle(message, state)
  end

  def handle(%__MODULE__{username: username} = message, %{conn: %Connection{} = conn} = state) do
    with {:ok, conn} <- get_session_key(conn, message),
         {:ok, conn} <- verify_proof(conn, message) do
      message =
        %Message.SmsgAuthResponse{
          result: 0x0C,
          billing_time: 0,
          billing_flags: 0,
          billing_rested: 0,
          queue_position: 0
        }

      {:ok, account} = ThistleTea.Account.get_user(username)

      %{state | conn: conn |> Connection.queue(message)}
      |> Map.put(:account, account)
    else
      _ ->
        message = %Message.SmsgAuthResponse{
          result: 0x0D
        }

        %{state | conn: conn |> Connection.queue(message)}
    end
  end

  def from_binary(payload) do
    with <<build::little-size(32), server_id::little-size(32), rest::binary>> <- payload,
         {:ok, username, rest} <- Util.parse_string(rest),
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

  defp get_session_key(%Connection{} = conn, %__MODULE__{username: username}) do
    case :ets.lookup(:session, username) do
      [{^username, session_key}] -> {:ok, Map.put(conn, :session_key, session_key)}
      _ -> {:error, conn}
    end
  end

  def verify_proof(%Connection{seed: seed, session_key: session_key} = conn, %__MODULE__{
        username: username,
        client_seed: client_seed,
        client_proof: client_proof
      }) do
    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> seed <> session_key
      )

    if client_proof == server_proof do
      {:ok, conn}
    else
      {:error, :proof_mismatch}
    end
  end
end
