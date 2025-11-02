defmodule ThistleTea.Game.Network.Connection do
  use ThistleTea.Game.Network.Opcodes, [:CMSG_AUTH_SESSION]

  alias ThistleTea.Game.Network.Connection.Crypto
  alias ThistleTea.Game.Network.Packet

  require Logger

  defstruct [
    :session_key,
    binary_stream: <<>>,
    packet_queue: [],
    send_i: 0,
    send_j: 0,
    recv_i: 0,
    recv_j: 0,
    seed: :crypto.strong_rand_bytes(4)
  ]

  def receive_data(%__MODULE__{} = conn, data) do
    Map.put(conn, :binary_stream, conn.binary_stream <> data)
  end

  # full header is 6 bytes, so any less is incomplete
  def enqueue_packets(%__MODULE__{binary_stream: binary_stream} = conn) when byte_size(binary_stream) < 6 do
    conn
  end

  # handle separately since this isn't encrypted
  def enqueue_packets(
        %__MODULE__{
          binary_stream:
            <<size::big-size(16), @cmsg_auth_session::little-size(32), payload::binary-size(size - 4), rest::binary>>
        } = conn
      ) do
    packet = %Packet{
      opcode: @cmsg_auth_session,
      size: size,
      payload: payload
    }

    Map.merge(conn, %{
      binary_stream: rest,
      packet_queue: conn.packet_queue ++ [packet]
    })
    |> enqueue_packets()
  end

  def enqueue_packets(%__MODULE__{} = conn) do
    case Crypto.decrypt_header(conn) do
      {:ok, conn, decrypted_header} ->
        <<size::big-size(16), opcode::little-size(32)>> = decrypted_header

        <<_encrypted_header::bytes-size(6), payload::binary-size(size - 4), rest::binary>> =
          conn.binary_stream

        packet = %Packet{
          opcode: opcode,
          size: size,
          payload: payload
        }

        Map.merge(conn, %{
          binary_stream: rest,
          packet_queue: conn.packet_queue ++ [packet]
        })
        |> enqueue_packets()

      {:error, conn, _} ->
        conn
    end
  end
end
