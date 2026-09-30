defmodule ThistleTea.Game.Inbound.Session do
  @moduledoc """
  Inbound side of a client connection, given to the network listener at
  startup. Decodes packets into client messages and routes each one: pings
  and everything before a player entity exists are handled against the
  connection's state, and the rest goes to the player's process.
  """
  @behaviour ThistleTea.Game.Network.Session

  alias ThistleTea.Game.Inbound.CmsgPing
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.World.ClientInput
  alias ThistleTea.Game.World.Entity.Player

  @impl Network.Session
  def decode(packet) do
    if Dispatch.implemented?(packet.opcode), do: {:ok, Dispatch.to_message(packet)}, else: :error
  end

  @impl Network.Session
  def handle_message(%CmsgPing{} = message, state), do: ClientInput.handle(message, state)

  def handle_message(message, %ConnectionState{player_pid: player_pid} = state) when is_pid(player_pid) do
    :ok = Player.handle_message(player_pid, message)
    state
  catch
    :exit, {reason, {GenServer, :call, [^player_pid | _args]}}
    when reason in [:noproc, :normal, {:shutdown, :logout}] ->
      state
  end

  def handle_message(message, state), do: ClientInput.handle(message, state)

  @impl Network.Session
  def disconnect(player_pid), do: Player.disconnect(player_pid)
end
