defmodule ThistleTea.Game do
  use ThousandIsland.Handler

  require Logger

  alias ThistleTea.CryptoStorage

  use ThistleTea.Game.Auth
  use ThistleTea.Game.Character
  use ThistleTea.Game.Chat
  use ThistleTea.Game.Login
  use ThistleTea.Game.Logout
  use ThistleTea.Game.Movement
  use ThistleTea.Game.Name
  use ThistleTea.Game.Ping

  @smsg_update_object 0x0A9
  @smsg_compressed_update_object 0x1F6

  def handle_packet(opcode, size, body) do
    GenServer.cast(self(), {:handle_packet, opcode, size, body})
  end

  def send_packet(opcode, payload) do
    GenServer.cast(self(), {:send_packet, opcode, payload})
  end

  def send_update_packet(packet) do
    Logger.info("[GameServer] Update: #{inspect(packet, limit: :infinity)}")
    compressed_packet = :zlib.compress(packet)
    original_size = byte_size(packet)
    compressed_size = byte_size(compressed_packet)

    if compressed_size >= original_size do
      send_packet(@smsg_update_object, packet)
    else
      send_packet(
        @smsg_compressed_update_object,
        <<original_size::little-size(32)>> <> compressed_packet
      )
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<header::bytes-size(6), body::binary>>,
        _socket,
        state
      ) do
    case CryptoStorage.decrypt_header(state.crypto_pid, header, byte_size(body) + 4) do
      {:ok, <<size::big-size(16), opcode::little-size(32)>>} ->
        handle_packet(opcode, size, body)
        {:continue, state}

      {:error, <<_size::big-size(16), opcode::little-size(32)>>} ->
        Logger.error("[GameServer] Received unencrypted #{inspect(opcode, base: :hex)} packet")
        {:continue, state}

      other ->
        Logger.error("[GameServer] ???: #{inspect(other, limit: :infinity)}")
        {:continue, state}
    end
  end

  @impl GenServer
  def handle_cast({:handle_packet, opcode, _size, _body}, {socket, state}) do
    Logger.error("[GameServer] Unhandled packet: #{inspect(opcode, base: :hex)}")
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:send_packet, opcode, payload}, {socket, state}) do
    CryptoStorage.send_packet(
      state.crypto_pid,
      opcode,
      payload,
      socket
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:send_packet, opcode, payload}, {socket, state}) do
    send_packet(opcode, payload)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:send_update_packet, packet}, {socket, state}) do
    send_update_packet(packet)
    {:noreply, {socket, state}, socket.read_timeout}
  end
end
