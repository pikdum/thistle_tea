defmodule ThistleTea.GameProxy do
  use ThousandIsland.Handler

  @timeout 5000

  @impl ThousandIsland.Handler
  def handle_data(data, client_socket, state) do
    case :gen_tcp.connect({127, 0, 0, 1}, 8084, [:binary, active: false]) do
      {:ok, target_socket} ->
        IO.inspect(data, label: "(Game) Sending to server:")
        :gen_tcp.send(target_socket, data)
        handle_response(client_socket, target_socket, state)

      {:error, reason} ->
        IO.inspect(reason, label: "Failed to connect to target server")
    end

    {:continue, state}
  end

  defp handle_response(client_socket, target_socket, state) do
    case :gen_tcp.recv(target_socket, 0, @timeout) do
      {:ok, response} ->
        IO.inspect(response, label: "(Game) Sending to client:")
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
        IO.inspect(data, label: "(Game) Sending to server:")
        :gen_tcp.send(target_socket, data)
        handle_response(client_socket, target_socket, state)

      {:error, :closed} ->
        IO.puts("Client closed connection")

      {:error, reason} ->
        IO.inspect(reason, label: "Failed to receive data from client")
    end
  end
end
