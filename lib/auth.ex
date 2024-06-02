defmodule ThistleTea.Auth do
  use ThousandIsland.Handler

  @cmd_auth_logon_challenge 0

  @impl ThousandIsland.Handler
  def handle_data(<<@cmd_auth_logon_challenge, data::binary>>, socket, state) do
    IO.inspect("CMD_AUTH_LOGON_CHALLENGE")

    <<
      size::binary-size(4),
      rest::binary
    >> = data

    IO.inspect(size, base: :binary)

    # IO.inspect(rest)
    ThousandIsland.Socket.send(socket, <<0>>)
    {:continue, state}
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    IO.inspect("UNHANDLED")
    <<msg::binary-size(1), rest::binary>> = data
    IO.inspect(msg, data)
    ThousandIsland.Socket.send(socket, data)
    {:continue, state}
  end
end
