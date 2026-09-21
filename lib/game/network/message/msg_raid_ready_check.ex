defmodule ThistleTea.Game.Network.Message.MsgRaidReadyCheck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_RAID_READY_CHECK

  alias ThistleTea.Game.Player.Groups

  defstruct [:ready?]

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
  def from_binary(<<flag>>) when flag in [0, 1], do: %__MODULE__{ready?: flag == 1}

  @impl ClientMessage
  def handle(%__MODULE__{ready?: ready?}, state), do: Groups.ready_check(state, ready?)
end
