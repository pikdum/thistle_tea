defmodule ThistleTeaGame.Connection do
  defstruct [
    :session_key,
    packet_stream: <<>>,
    packet_queue: [],
    send_i: 0,
    send_j: 0,
    recv_i: 0,
    recv_j: 0
  ]

  alias ThistleTeaGame.Connection.Crypto

  def receive_data(%__MODULE__{} = conn, data) do
    Map.put(conn, :packet_stream, Map.get(conn, :packet_stream, <<>>) <> data)
  end

  def enqueue_packets(%__MODULE__{} = conn) do
    case Crypto.decrypt_header(conn) do
      {:ok, conn, decrypted_header} ->
        <<size::big-size(16), opcode::little-size(32)>> = decrypted_header

        <<_encrypted_header::bytes-size(6), payload::binary-size(size - 4), rest::binary>> =
          conn.packet_stream

        packet = %{
          opcode: opcode,
          size: size,
          payload: payload
        }

        conn =
          Map.merge(conn, %{
            packet_stream: rest,
            packet_queue: conn.packet_queue ++ [packet]
          })

        enqueue_packets(conn)

      {:error, conn, _} ->
        conn
    end
  end
end
