defmodule ThistleTea.Game.Network.Connection.Crypto do
  alias ThistleTea.Game.Network.Connection

  def decrypt_header(%Connection{session_key: session_key} = conn) when is_nil(session_key) do
    {:error, conn, :no_session_key}
  end

  def decrypt_header(%Connection{binary_stream: <<header::bytes-size(6), rest::binary>>} = conn) do
    {decrypted_header, recv_i, recv_j} =
      decrypt_bytes(header, conn.session_key, byte_size(conn.session_key), conn.recv_i, conn.recv_j, <<>>)

    rest_size = byte_size(rest)
    <<size::big-size(16), _opcode::little-size(32)>> = decrypted_header

    if rest_size < size - 4 do
      {:error, conn, :not_enough_data}
    else
      {:ok, %{conn | recv_i: recv_i, recv_j: recv_j}, decrypted_header}
    end
  end

  def decrypt_header(%Connection{} = conn), do: {:error, conn, :not_enough_data}

  def encrypt_header(%Connection{} = conn, header) do
    {encrypted_header, send_i, send_j} =
      encrypt_bytes(header, conn.session_key, byte_size(conn.session_key), conn.send_i, conn.send_j, <<>>)

    {:ok, %{conn | send_i: send_i, send_j: send_j}, encrypted_header}
  end

  defp decrypt_bytes(<<>>, _session_key, _key_size, recv_i, recv_j, acc) do
    {acc, recv_i, recv_j}
  end

  defp decrypt_bytes(<<byte, rest::binary>>, session_key, key_size, recv_i, recv_j, acc) do
    key_index = rem(recv_i, key_size)
    x = Bitwise.bxor(byte - recv_j, :binary.at(session_key, key_index))
    <<truncated_x>> = <<x::little-size(8)>>
    decrypt_bytes(rest, session_key, key_size, key_index + 1, byte, <<acc::binary, truncated_x>>)
  end

  defp encrypt_bytes(<<>>, _session_key, _key_size, send_i, send_j, acc) do
    {acc, send_i, send_j}
  end

  defp encrypt_bytes(<<byte, rest::binary>>, session_key, key_size, send_i, send_j, acc) do
    key_index = rem(send_i, key_size)
    x = Bitwise.bxor(byte, :binary.at(session_key, key_index)) + send_j
    <<truncated_x>> = <<x::little-size(8)>>
    encrypt_bytes(rest, session_key, key_size, key_index + 1, truncated_x, <<acc::binary, truncated_x>>)
  end
end
