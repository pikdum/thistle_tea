defmodule ThistleTea.Game.Network.ConnectionState do
  @moduledoc """
  Authentication and player-attachment state owned by a client connection.

  Gameplay state lives in the attached player entity; the connection retains
  only protocol state and enough information to route messages to that owner,
  including the last character played, for client caches uploaded after logout.
  """

  alias ThistleTea.Game.Network.Connection

  defstruct [:account, :player_pid, :player_monitor, :character_guid, :latency, :session, conn: %Connection{}]

  @type t :: %__MODULE__{}

  def attach_player(%__MODULE__{player_pid: nil} = state, player_pid, character_guid \\ nil) when is_pid(player_pid) do
    %{state | player_pid: player_pid, player_monitor: Process.monitor(player_pid), character_guid: character_guid}
  end

  def clear_player(%__MODULE__{} = state) do
    if is_reference(state.player_monitor), do: Process.demonitor(state.player_monitor, [:flush])

    %__MODULE__{
      account: state.account,
      character_guid: state.character_guid,
      latency: state.latency,
      session: state.session,
      conn: state.conn
    }
  end
end
