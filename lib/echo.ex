defmodule ThistleTea.Echo do
  use ThousandIsland.Handler

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    IO.inspect(data)
    ThousandIsland.Socket.send(socket, data)
    {:continue, state}
  end
end
