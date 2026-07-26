defmodule ThistleTea.Game.Network.ConnectionState do
  @moduledoc """
  Authentication and player-attachment state owned by a client connection.

  Gameplay state lives in the attached player entity; the connection retains
  only protocol state and enough information to route messages to that owner.
  """

  alias ThistleTea.Game.Network.Connection

  defstruct [:account, :player_pid, :player_monitor, :latency, conn: %Connection{}]

  def attach_player(%__MODULE__{player_pid: nil} = state, player_pid) when is_pid(player_pid) do
    %{state | player_pid: player_pid, player_monitor: Process.monitor(player_pid)}
  end

  def clear_player(%__MODULE__{} = state) do
    if is_reference(state.player_monitor), do: Process.demonitor(state.player_monitor, [:flush])
    %__MODULE__{account: state.account, latency: state.latency, conn: state.conn}
  end
end
