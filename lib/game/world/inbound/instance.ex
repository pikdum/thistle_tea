defmodule ThistleTea.Game.World.Inbound.Instance do
  @moduledoc "Handles decoded instance lock client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Instances
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

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
    case InstanceSystem.reset(guid) do
      {:ok, %{reset: reset, failed: failed}} ->
        Enum.each(reset, fn world ->
          Outbound.send_packet(%Message.SmsgInstanceReset{map: world.map_id})
        end)

        Enum.each(failed, fn world ->
          Outbound.send_packet(%Message.SmsgInstanceResetFailed{reason: 0, map: world.map_id})
        end)

      {:error, :not_leader} ->
        :ok
    end

    state
  end

  def handle(%Message.CmsgResetInstances{}, state), do: state
end
