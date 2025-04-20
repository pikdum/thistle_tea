defmodule ThistleTeaGame.Connection.Crypto do
  alias ThistleTeaGame.Connection

  def decrypt_header(%Connection{session_key: session_key} = conn) when is_nil(session_key) do
    {:error, conn, :no_session_key}
  end

  def decrypt_header(
        %Connection{
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

  def decrypt_header(%Connection{} = conn), do: {:error, conn, :not_enough_data}

  def encrypt_header(%Connection{} = conn, header) do
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

  def verify_proof(%Connection{} = conn, username, client_seed, client_proof) do
    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> conn.seed <> conn.session_key
      )

    if client_proof == server_proof do
      {:ok, conn}
    else
      {:error, nil}
    end
  end
end
