defmodule ThistleTea.Auth do
  use ThousandIsland.Handler

  require Logger

  alias ThistleTea.SessionStorage

  import Binary, only: [reverse: 1]

  @cmd_auth_logon_challenge 0
  @cmd_auth_logon_proof 1
  @cmd_auth_reconnect_challenge 2
  @cmd_auth_reconnect_proof 3
  @cmd_realm_list 16

  @n <<137, 75, 100, 94, 137, 225, 83, 91, 189, 173, 91, 139, 41, 6, 80, 83, 8, 1, 177, 142, 191,
       191, 94, 143, 171, 60, 130, 135, 42, 62, 155, 183>>
  @g <<7>>

  @salt <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0>>

  defp calculate_b(state) do
    private_b = :crypto.strong_rand_bytes(19)
    Map.merge(state, %{private_b: private_b})
  end

  defp calculate_B(state) do
    {public_b, _} =
      :crypto.generate_key(
        :srp,
        {:host, [state.verifier, state.g, state.n, :"6"]},
        state.private_b
      )

    Map.merge(state, %{public_b: public_b})
  end

  # TODO: password hardcoded to pikdum
  defp account_state(account) do
    %{n: @n, g: @g}
    |> Map.merge(%{account_name: account})
    |> Map.merge(%{
      verifier:
        <<34, 54, 51, 44, 77, 56, 96, 52, 2, 253, 163, 246, 128, 63, 103, 166, 81, 9, 71, 120, 41,
          87, 250, 125, 141, 73, 124, 172, 157, 84, 95, 126>>
    })
    |> Map.merge(%{
      salt: @salt
    })
  end

  defp logon_challenge_state(account) do
    account_state(account)
    |> calculate_b()
    |> calculate_B()
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<@cmd_auth_logon_challenge, _protocol_version::little-size(8), _size::little-size(16),
          _game_name::bytes-little-size(4), _version::bytes-little-size(3),
          _build::little-size(16), _platform::bytes-little-size(4), _os::bytes-size(4),
          _locale::bytes-size(4), _worldregion_bias::little-size(32), _ip::little-size(32),
          account_name_length::unsigned-little-size(8),
          account_name::bytes-little-size(account_name_length)>>,
        socket,
        _state
      ) do
    Logger.info("[AuthServer] CMD_AUTH_LOGON_CHALLENGE: #{account_name}, pid: #{inspect(self())}")
    state = logon_challenge_state(account_name)

    packet =
      <<0, 0, 0>> <>
        reverse(state.public_b) <>
        <<1>> <>
        state.g <>
        <<32>> <> reverse(state.n) <> state.salt <> :crypto.strong_rand_bytes(16) <> <<0>>

    ThousandIsland.Socket.send(socket, packet)
    {:continue, state}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<@cmd_auth_logon_proof, client_public_key::little-bytes-size(32),
          client_proof::little-bytes-size(20), _crc_hash::little-bytes-size(20),
          _num_keys::little-size(8), _security_flags::little-size(8)>>,
        socket,
        state
      ) do
    Logger.info("[AuthServer] CMD_AUTH_LOGON_PROOF: #{state.account_name}")
    public_a = reverse(client_public_key)
    scrambler = :crypto.hash(:sha, reverse(public_a) <> reverse(state.public_b))

    s =
      reverse(
        :crypto.compute_key(
          :srp,
          public_a,
          {state.public_b, state.private_b},
          {:host, [state.verifier, @n, :"6", reverse(scrambler)]}
        )
      )

    session = interleave(s)

    mod_hash = :crypto.hash(:sha, reverse(@n))
    generator_hash = :crypto.hash(:sha, @g)
    t3 = :crypto.exor(mod_hash, generator_hash)
    t4 = :crypto.hash(:sha, state.account_name)

    m =
      :crypto.hash(
        :sha,
        t3 <> t4 <> state.salt <> reverse(public_a) <> reverse(state.public_b) <> session
      )

    if m == client_proof do
      server_proof = :crypto.hash(:sha, reverse(public_a) <> client_proof <> session)

      state =
        Map.merge(state, %{public_a: public_a, session: session, server_proof: server_proof})

      :ets.insert(:session, {state.account_name, state.session})

      ThousandIsland.Socket.send(socket, <<1, 0>> <> state.server_proof <> <<0, 0, 0, 0>>)
      {:continue, state}
    else
      Logger.error("[AuthServer] Authentication failed: #{state.account_name}")
      ThousandIsland.Socket.send(socket, <<0, 0, 5>>)
      {:close, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(<<@cmd_realm_list, _padding::binary>>, socket, state) do
    Logger.info("[AuthServer] CMD_REALM_LIST")

    ip = Application.fetch_env!(:thistle_tea, :ip)

    realm =
      <<8::little-size(32), 0::little-size(8)>> <>
        "kuudere.moe" <>
        <<0>> <>
        "#{ip}:8085" <> <<0>> <> <<200::little-float-size(32), 0::size(8), 0::size(8), 0>>

    num_realms = 1

    header = <<16, byte_size(realm) + 7::little-size(16), 0, 0, 0, 0, num_realms>>
    body = realm <> <<2, 0>>
    packet = header <> body
    ThousandIsland.Socket.send(socket, packet)
    {:continue, state}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<@cmd_auth_reconnect_challenge, _protocol_version::little-size(8),
          _size::little-size(16), _game_name::bytes-little-size(4),
          _version::bytes-little-size(3), _build::little-size(16),
          _platform::bytes-little-size(4), _os::bytes-little-size(4),
          _locale::bytes-little-size(4), _worldregion_bias::little-size(32), _ip::little-size(32),
          account_name_length::little-size(8),
          account_name::bytes-little-size(account_name_length)>>,
        socket,
        state
      ) do
    Logger.info("[AuthServer] CMD_AUTH_RECONNECT_CHALLENGE: #{account_name}")
    # TODO: need to get salt from account storage
    # and need to test this flow more in-depth
    challenge_data = :crypto.strong_rand_bytes(16)
    ThousandIsland.Socket.send(socket, <<2, 0>> <> challenge_data <> @salt)
    {:continue, Map.merge(state, %{account_name: account_name, challenge_data: challenge_data})}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<@cmd_auth_reconnect_proof, proof_data::little-bytes-size(16),
          client_proof::little-bytes-size(20), _client_checksum::little-bytes-size(20),
          _key_count>>,
        socket,
        state
      ) do
    Logger.info("[AuthServer] CMD_AUTH_RECONNECT_PROOF: #{state.account_name}")
    session = SessionStorage.get(state.account_name)

    server_proof =
      :crypto.hash(:sha, state.account_name <> proof_data <> state.challenge_data <> session)

    if client_proof === server_proof do
      Logger.info("[AuthServer] CMD_AUTH_RECONNECT_PROOF: success: #{state.account_name}")
      {:continue, state}
      ThousandIsland.Socket.send(socket, <<3, 0>>)
    else
      ThousandIsland.Socket.send(socket, <<3, 1>>)
      {:close, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(<<opcode, _packet::binary>>, socket, state) do
    Logger.error("[AuthServer] Unimplemented opcode: #{opcode}")
    ThousandIsland.Socket.send(socket, <<0, 0, 5>>)
    {:close, state}
  end

  defp interleave(s) do
    list = Binary.to_list(s)

    t1 = Binary.from_list(interleave_t1(list))
    t2 = Binary.from_list(interleave_t2(list))

    t1_hash = Binary.to_list(:crypto.hash(:sha, t1))
    t2_hash = Binary.to_list(:crypto.hash(:sha, t2))

    Binary.from_list(List.flatten(Enum.map(List.zip([t1_hash, t2_hash]), &Tuple.to_list/1)))
  end

  defp interleave_t1([a, _ | rest]), do: [a | interleave_t1(rest)]
  defp interleave_t1([]), do: []

  defp interleave_t2([_, b | rest]), do: [b | interleave_t2(rest)]
  defp interleave_t2([]), do: []
end
