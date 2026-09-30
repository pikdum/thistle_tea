defmodule ThistleTea.Game.Network.Session do
  @moduledoc """
  The layer above the network that decodes and handles client messages. The
  application supplies the implementation through the game listener's
  handler options, so the network layer never references it directly.
  """
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.Network.Packet

  @callback decode(packet :: %Packet{}) :: {:ok, struct()} | :error
  @callback handle_message(message :: struct(), state :: ConnectionState.t()) :: ConnectionState.t()
  @callback disconnect(player_pid :: pid()) :: :ok
end
