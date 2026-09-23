defmodule ThistleTea.Game.Network.Message.CmsgRequestRaidInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REQUEST_RAID_INFO

  alias ThistleTea.Game.Player.Instances

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid} = state) do
    Instances.send_raid_info(guid)
    state
  end

  def handle(%__MODULE__{}, state), do: state
end
