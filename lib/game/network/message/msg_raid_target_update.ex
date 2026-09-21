defmodule ThistleTea.Game.Network.Message.MsgRaidTargetUpdate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_RAID_TARGET_UPDATE

  alias ThistleTea.Game.Player.Groups

  defstruct [:icon, :target]

  @impl ClientMessage
  def from_binary(<<0xFF>>), do: %__MODULE__{icon: 0xFF}

  def from_binary(<<icon::little-size(8), target::little-size(64)>>), do: %__MODULE__{icon: icon, target: target}

  @impl ClientMessage
  def handle(%__MODULE__{icon: icon, target: target}, state), do: Groups.target_icon(state, icon, target)
end
