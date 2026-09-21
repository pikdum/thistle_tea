defmodule ThistleTea.Game.Network.Message.CmsgGroupRaidConvert do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_RAID_CONVERT

  alias ThistleTea.Game.Player.Groups

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Groups.convert_raid(state)
end
