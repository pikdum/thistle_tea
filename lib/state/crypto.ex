defmodule ThistleTea.CryptoStorage do
  use GenServer

  import Bitwise, only: [bxor: 2]

  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial)
  end

  def encrypt_header(pid, opcode, payload) do
    GenServer.call(pid, {:encrypt_header, opcode, payload})
  end

  def decrypt_header(pid, header) do
    GenServer.call(pid, {:decrypt_header, header})
  end

  @impl true
  def init(initial) do
    {:ok, initial}
  end

  @impl true
  def handle_call({:encrypt_header, opcode, payload}, _from, state) do
    size = byte_size(payload) + 2
    header = <<size::big-size(16), opcode::little-size(16)>>
    {encrypted_header, new_state} = internal_encrypt_header(header, state)
    {:reply, {:ok, encrypted_header}, new_state}
  end

  @impl true
  def handle_call({:decrypt_header, header}, _from, state) do
    {decrypted_header, new_state} = internal_decrypt_header(header, state)
    {:reply, {:ok, decrypted_header}, new_state}
  end

  defp internal_encrypt_header(header, state) do
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

  defp internal_decrypt_header(header, state) do
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
