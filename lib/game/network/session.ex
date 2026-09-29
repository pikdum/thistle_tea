defmodule ThistleTea.Game.Network.Session do
  @moduledoc """
  Receiver of decoded client messages for a world connection. The application
  supplies the implementation through the game listener's handler options, so
  the network layer never references the world directly.

  Messages that arrive before a player entity exists are handled with the
  connection's own state; afterwards they are forwarded to the player process.
  """
  alias ThistleTea.Game.Network.ConnectionState

  @callback handle_message(message :: struct(), state :: ConnectionState.t()) :: ConnectionState.t()
  @callback forward(player_pid :: pid(), message :: struct()) :: :ok
  @callback disconnect(player_pid :: pid()) :: :ok
end
