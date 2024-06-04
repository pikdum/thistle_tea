defmodule ThistleTea.Game do
  use ThousandIsland.Handler
  require Logger

  import Binary, only: [split_at: 2, trim_trailing: 1, pad_trailing: 2]
  import Bitwise, only: [bxor: 2]

  @cmsg_auth_session 0x1ED

  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    # send SMSG_AUTH_CHALLENGE
    seed = :crypto.strong_rand_bytes(4)
    Logger.info("[GameServer] Sending SMSG_AUTH_CHALLENGE with seed: #{inspect(seed)}")
    ThousandIsland.Socket.send(socket, <<6::big-size(16), 0x1EC::little-size(16)>> <> seed)
    {:continue, %{seed: seed}}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<size::big-size(16), @cmsg_auth_session::little-size(32), body::binary-size(size - 4)>>,
        socket,
        state
      ) do
    <<build::little-size(32), server_id::little-size(32), rest::binary>> = body

    Logger.info(
      "[GameServer] Received CMSG_AUTH_SESSION with build: #{build}, server_id: #{server_id}"
    )

    {:ok, username, rest} = parse_string(rest)
    Logger.info("[GameServer] Username: #{username}")

    <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> =
      rest

    session = ThistleTea.SessionStorage.get(username)

    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> state.seed <> session
      )

    if client_proof == server_proof do
      Logger.info("[GameServer] Authentication successful for #{username}")
      crypt = %{key: session, send_i: 0, send_j: 0, recv_i: 0, recv_j: 0}

      # TODO: keeping track of crypt seems like it's synchronous, so try a different abtraction rather than using state
      {packet, crypt} =
        build_packet(0x1EE, <<0x0C, 0::little-size(32), 0, 0::little-size(32)>>, crypt)

      Logger.info("[GameServer] Packet: #{inspect(packet, limit: :infinity)}")

      ThousandIsland.Socket.send(
        socket,
        packet
      )

      {:continue, Map.merge(state, %{username: username, crypt: crypt})}
    else
      Logger.error("[GameServer] Authentication failed for #{username}")
      {:close, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(
        packet,
        _socket,
        state
      ) do
    Logger.error("[GameServer] Unhandled packet: #{inspect(packet, limit: :infinity)})}")
    {:continue, state}
  end

  def encrypt_header(header, state) do
    initial_acc = {<<>>, %{send_i: state.send_i, send_j: state.send_j}}

    {header, crypt_state} =
      Enum.reduce(
        :binary.bin_to_list(header),
        initial_acc,
        fn byte, {header, crypt} ->
          send_i = rem(crypt.send_i, byte_size(state.key))
          x = bxor(byte, :binary.at(state.key, send_i)) + crypt.send_j
          <<truncated_x>> = <<x::little-size(8)>>
          {header <> <<truncated_x>>, %{send_i: send_i + 1, send_j: truncated_x}}
        end
      )

    {header, Map.merge(state, crypt_state)}
  end

  defp build_packet(opcode, payload) do
    size = byte_size(payload) + 2
    header = <<size::big-size(16), opcode::little-size(16)>>
    header <> payload
  end

  defp build_packet(opcode, payload, crypt) do
    size = byte_size(payload) + 2
    header = <<size::big-size(16), opcode::little-size(16)>>

    Logger.info(
      "[GameServer] Encrypting header: #{inspect(header)} with crypt: #{inspect(crypt)}"
    )

    {encrypted_header, new_crypt} = encrypt_header(header, crypt)

    Logger.info(
      "[GameServer] Encrypted header: #{inspect(encrypted_header)} with new crypt: #{inspect(new_crypt)}"
    )

    {encrypted_header <> payload, new_crypt}
  end

  def parse_string(payload, pos \\ 1)
  def parse_string(payload, _pos) when byte_size(payload) == 0, do: {:ok, payload, <<>>}

  def parse_string(payload, pos) do
    case :binary.at(payload, pos - 1) do
      0 ->
        {string, rest} = split_at(payload, pos)
        {:ok, trim_trailing(string), rest}

      _ ->
        parse_string(payload, pos + 1)
    end
  end
end
