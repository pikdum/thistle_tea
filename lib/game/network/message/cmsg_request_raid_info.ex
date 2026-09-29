defmodule ThistleTea.Game.Network.Message.CmsgRequestRaidInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REQUEST_RAID_INFO

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
