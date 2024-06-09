defmodule ThistleTea.CryptoStorage do
  use GenServer

  import Bitwise, only: [bxor: 2]

  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial)
  end

  def send_packet(pid, opcode, payload, socket) do
    GenServer.cast(pid, {:send_packet, opcode, payload, socket})
  end

  def decrypt_header(pid, header, expected_size) do
    GenServer.call(pid, {:decrypt_header, header, expected_size})
  end

  @impl true
  def init(initial) do
    {:ok, initial}
  end

  @impl true
  def handle_cast({:send_packet, opcode, payload, socket}, state) do
    # do these actually need to be sent, or just encrypted?
    size = byte_size(payload) + 2
    header = <<size::big-size(16), opcode::little-size(16)>>
    {encrypted_header, new_state} = encrypt_header(header, state)
    ThousandIsland.Socket.send(socket, encrypted_header <> payload)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:decrypt_header, header, expected_size}, _from, state) do
    {decrypted_header, new_state} = decrypt_header(header, state)
    <<size::big-size(16), _opcode::little-size(32)>> = decrypted_header

    if size === expected_size do
      {:reply, {:ok, decrypted_header}, new_state}
    else
      {:reply, {:error, header}, state}
    end
  end

  defp encrypt_header(header, state) do
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

  def decrypt_header(header, state) do
    initial_acc = {<<>>, %{recv_i: state.recv_i, recv_j: state.recv_j}}

    {header, crypt_state} =
      Enum.reduce(
        :binary.bin_to_list(header),
        initial_acc,
        fn byte, {header, crypt} ->
          recv_i = rem(crypt.recv_i, byte_size(state.key))
          x = bxor(byte - crypt.recv_j, :binary.at(state.key, recv_i))
          <<truncated_x>> = <<x::little-size(8)>>
          {header <> <<truncated_x>>, %{recv_i: recv_i + 1, recv_j: byte}}
        end
      )

    {header, Map.merge(state, crypt_state)}
  end
end
