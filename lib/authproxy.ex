defmodule ThistleTea.AuthProxy do
  use ThousandIsland.Handler

  @timeout 5000

  def parse_packet(data, state) do
    <<opcode, rest::binary>> = data
    IO.inspect(opcode, label: "Opcode")

    if opcode == 1 do
      <<a::binary-size(32), m1::binary-size(20), crc_hash::binary-size(20), number_of_keys,
        security_flags>> = rest

      # A = client_public_value
      IO.inspect(a, label: "A")
      # M1 = ???
      IO.inspect(m1, label: "M1")
      IO.inspect(crc_hash, label: "CRC Hash")
      IO.inspect(number_of_keys, label: "Number of keys")
      IO.inspect(security_flags, label: "Security Flags")
      server = state[:server]
      # private_server_session_key = Strap.session_key(server, a)
      IO.inspect(private_server_session_key, label: "Private Server Session Key")
    end

    if opcode == 0 do
      <<error, size::16, rest::binary>> = rest
      IO.inspect(error, label: "Error")
      IO.inspect(size / 32, label: "Size")
      IO.inspect(byte_size(rest) * 8, label: "Rest size")
      # if size != calculated size, can throw error later
      <<gamename1, gamename2, gamename3, gamename4, version1, version2, version3, build::16,
        platform1, platform2, platform3, platform4, os1, os2, os3, os4, country1, country2,
        country3, country4, timezone_bias::32, ip::32, input_length, rest::binary>> = rest

      IO.inspect(gamename1, label: "Gamename1")
      IO.inspect(gamename2, label: "Gamename2")
      IO.inspect(gamename3, label: "Gamename3")
      IO.inspect(gamename4, label: "Gamename4")
      IO.inspect(version1, label: "Version1")
      IO.inspect(version2, label: "Version2")
      IO.inspect(version3, label: "Version3")
      IO.inspect(build, label: "Build")
      IO.inspect(platform1, label: "Platform1")
      IO.inspect(platform2, label: "Platform2")
      IO.inspect(platform3, label: "Platform3")
      IO.inspect(platform4, label: "Platform4")
      IO.inspect(os1, label: "OS1")
      IO.inspect(os2, label: "OS2")
      IO.inspect(os3, label: "OS3")
      IO.inspect(os4, label: "OS4")
      IO.inspect(country1, label: "Country1")
      IO.inspect(country2, label: "Country2")
      IO.inspect(country3, label: "Country3")
      IO.inspect(country4, label: "Country4")
      IO.inspect(timezone_bias, label: "Timezone Bias")
      IO.inspect(ip, label: "IP")
      IO.inspect(input_length, label: "Input Length")

      # can check input size here too
      <<input::binary-size(input_length)>> = rest

      IO.inspect(input, label: "Input")

      sha_pass_hash = Base.decode16!("c0b3ebf26d15b7182e0b651335b2e3e5dadde2a3", case: :lower)
      v = 0x2761B511883A92AF9E5A430683901F4936F9EFC48554F3D0B5567528E2696CF3
      s = Base.decode16!("A5E024D3D97D9C56A10BEA50E2E5DD9C4046C8C091F5884112CE82A608D47A5B")

      n = Base.decode16!("894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7")
      g = 7

      # server = Strap.protocol(:srp6a, n, g) |> Strap.server(v)
      # b = Strap.public_value(server)

      reversed_n = :binary.bin_to_list(n) |> Enum.reverse() |> :binary.list_to_bin()
      reversed_s = :binary.bin_to_list(s) |> Enum.reverse() |> :binary.list_to_bin()

      # should B be reversed too?
      # not sure how to test, since this has some randomness
      IO.inspect(b, label: "B")
      # looks good, just an int
      IO.inspect(g, label: "g")
      # looks good, had to reverse
      IO.inspect(reversed_n, label: "N")
      # looks good, had to reverse
      IO.inspect(reversed_s, label: "s")

      # generate random 16 bytes
      random = :crypto.strong_rand_bytes(16)
      IO.inspect(random, label: "Random")

      %{server: server, b: b, g: g, n: reversed_n, s: reversed_s, random: random}

      # <<0, 0, 0, B::32, 1, g, 32, N::32, s::32, random::16, 0>>
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(data, client_socket, state) do
    IO.inspect(state, label: "State")

    case :gen_tcp.connect({127, 0, 0, 1}, 3723, [:binary, active: false]) do
      {:ok, target_socket} ->
        IO.inspect(data, label: "(Auth) Sending to server:", limit: :infinity)
        auth_state = parse_packet(data, state)
        :gen_tcp.send(target_socket, data)
        handle_response(client_socket, target_socket, auth_state)

      {:error, reason} ->
        IO.inspect(reason, label: "Failed to connect to target server")
    end

    {:continue, state}
  end

  defp handle_response(client_socket, target_socket, state) do
    case :gen_tcp.recv(target_socket, 0, @timeout) do
      {:ok, response} ->
        IO.inspect(response, label: "(Auth) Sending to client:", limit: :infinity)
        ThousandIsland.Socket.send(client_socket, response)

      {:error, :closed} ->
        IO.puts("Target server closed connection")

      {:error, reason} ->
        IO.inspect(reason, label: "Failed to receive response from target server")
    end

    handle_client_data(client_socket, target_socket, state)
  end

  defp handle_client_data(client_socket, target_socket, state) do
    case ThousandIsland.Socket.recv(client_socket, 0, @timeout) do
      {:ok, data} ->
        IO.inspect(data, label: "(Auth) Sending to server:", limit: :infinity)
        parse_packet(data, state)
        :gen_tcp.send(target_socket, data)
        handle_response(client_socket, target_socket, state)

      {:error, :closed} ->
        IO.puts("Client closed connection")

      {:error, reason} ->
        IO.inspect(reason, label: "Failed to receive data from client")
    end
  end
end
