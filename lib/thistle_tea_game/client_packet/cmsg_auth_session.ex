defmodule ThistleTeaGame.ClientPacket.CmsgAuthSession do
  use ThistleTeaGame.ClientPacket, opcode: :CMSG_AUTH_SESSION

  defstruct [
    :build,
    :server_id,
    :username,
    :client_seed,
    :client_proof
  ]

  @impl ClientPacket
  def handle(
        %__MODULE__{} = packet,
        %Connection{} = conn
      ) do
    case verify_proof(conn, packet) do
      {:ok, conn} ->
        effect = %Effect.SendPacket{
          packet: %ServerPacket.SmsgAuthResponse{
            result: 0x0C,
            billing_time: 0,
            billing_flags: 0,
            billing_rested: 0,
            queue_position: 0
          }
        }

        {:ok, conn |> Connection.add_effect(effect)}

      {:error, _} ->
        {:error, conn}
    end
  end

  @impl ClientPacket
  def decode(%ClientPacket{payload: payload}) do
    with <<build::little-size(32), server_id::little-size(32), rest::binary>> <- payload,
         {:ok, username, rest} <- ClientPacket.Parse.parse_string(rest),
         <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> <-
           rest do
      {:ok,
       %__MODULE__{
         build: build,
         server_id: server_id,
         username: username,
         client_seed: client_seed,
         client_proof: client_proof
       }}
    else
      _ -> {:error, :invalid_packet}
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
