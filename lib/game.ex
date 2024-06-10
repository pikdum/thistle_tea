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
        socket,
        state
      ) do
    case CryptoStorage.decrypt_header(state.crypto_pid, header) do
      {:ok, <<size::big-size(16), opcode::little-size(32)>>} ->
        payload_size = size - 4
        <<payload::binary-size(payload_size), additional_data::binary>> = body
        if byte_size(additional_data) > 0, do: handle_data(additional_data, socket, state)

        handle_packet(opcode, size, payload)
        {:continue, state}

      other ->
        Logger.error("[GameServer] ???: #{inspect(other, limit: :infinity)}")
        {:continue, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(data, _socket, state) do
    Logger.error("[GameServer] Received unknown data: #{inspect(data, limit: :infinity)}")
    {:continue, state}
  end

  @impl GenServer
  def handle_cast({:handle_packet, opcode, _size, _body}, {socket, state}) do
    Logger.error("[GameServer] Unhandled packet: #{inspect(opcode, base: :hex)}")
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:send_packet, opcode, payload}, {socket, state}) do
    {:ok, header} = CryptoStorage.encrypt_header(state.crypto_pid, opcode, payload)
    ThousandIsland.Socket.send(socket, header <> payload)
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
