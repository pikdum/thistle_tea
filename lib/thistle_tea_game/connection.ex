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

  def receive_data(conn, data) do
    Map.put(conn, :packet_stream, Map.get(conn, :packet_stream, <<>>) <> data)
  end

  def decrypt_header(
        %ThistleTeaGame.Connection{
          packet_stream: <<header::bytes-size(6), rest::binary>>
        } = conn
      ) do
    initial_acc = {<<>>, %{recv_i: conn.recv_i, recv_j: conn.recv_j}}

    {decrypted_header, crypto_state} =
      Enum.reduce(
        :binary.bin_to_list(header),
        initial_acc,
        fn byte, {header, crypt} ->
          recv_i = rem(crypt.recv_i, byte_size(conn.session_key))
          x = Bitwise.bxor(byte - crypt.recv_j, :binary.at(conn.session_key, recv_i))
          <<truncated_x>> = <<x::little-size(8)>>
          {header <> <<truncated_x>>, %{recv_i: recv_i + 1, recv_j: byte}}
        end
      )

    new_conn = Map.merge(conn, crypto_state)

    rest_size = byte_size(rest)
    <<size::big-size(16), _opcode::little-size(32)>> = decrypted_header

    if rest_size < size - 4 do
      {:error, conn, :not_enough_data}
    else
      {:ok, new_conn, decrypted_header}
    end
  end

  def decrypt_header(conn), do: {:error, conn, :not_enough_data}

  def encrypt_header(conn, header) do
    initial_acc = {<<>>, %{send_i: conn.send_i, send_j: conn.send_j}}

    {encrypted_header, crypt_state} =
      Enum.reduce(
        :binary.bin_to_list(header),
        initial_acc,
        fn byte, {header, crypt} ->
          send_i = rem(crypt.send_i, byte_size(conn.session_key))
          x = Bitwise.bxor(byte, :binary.at(conn.session_key, send_i)) + crypt.send_j
          <<truncated_x>> = <<x::little-size(8)>>
          {header <> <<truncated_x>>, %{send_i: send_i + 1, send_j: truncated_x}}
        end
      )

    new_conn = Map.merge(conn, crypt_state)
    {:ok, new_conn, encrypted_header}
  end

  def enqueue_packets(conn) do
    case decrypt_header(conn) do
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
