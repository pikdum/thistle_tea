defmodule ThistleTea.Game.World.Inbound.Instance do
  @moduledoc "Handles decoded instance lock client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Instances

  def messages do
    [
      Message.CmsgRequestRaidInfo,
      Message.CmsgResetInstances
    ]
  end

  def handle(%Message.CmsgRequestRaidInfo{}, %{ready: true, guid: guid} = state) do
    Instances.send_raid_info(guid)
    state
  end

  def handle(%Message.CmsgRequestRaidInfo{}, state), do: state

  def handle(%Message.CmsgResetInstances{}, %{ready: true, guid: guid} = state) do
    Instances.reset(guid)
    state
  end

  def handle(%Message.CmsgResetInstances{}, state), do: state
end
