defmodule ThistleTea.Game.World.Session do
  @moduledoc """
  World side of a client connection: handles messages that arrive before a
  player entity exists and routes the rest into the player's process.
  """
  @behaviour ThistleTea.Game.Network.Session

  alias ThistleTea.Game.World.Entity.Player
  alias ThistleTea.Game.World.Inbound

  @impl true
  def handle_message(message, state), do: Inbound.handle(message, state)

  @impl true
  def forward(player_pid, message), do: Player.handle_message(player_pid, message)

  @impl true
  def disconnect(player_pid), do: Player.disconnect(player_pid)
end
