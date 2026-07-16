defmodule ThistleTea.Game.Network.Message.CmsgResetInstances do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_RESET_INSTANCES

  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid} = state) do
    case InstanceSystem.reset(guid) do
      {:ok, %{reset: reset, failed: failed}} ->
        Enum.each(reset, fn world ->
          Network.send_packet(%Message.SmsgInstanceReset{map: world.map_id})
        end)

        Enum.each(failed, fn world ->
          Network.send_packet(%Message.SmsgInstanceResetFailed{reason: 0, map: world.map_id})
        end)

      {:error, :not_leader} ->
        :ok
    end

    state
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
