defmodule ThistleTea.Game.Network.Message.CmsgGroupRaidConvert do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_RAID_CONVERT

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
