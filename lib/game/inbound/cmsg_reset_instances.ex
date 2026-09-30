defmodule ThistleTea.Game.Inbound.CmsgResetInstances do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_RESET_INSTANCES

  alias ThistleTea.Game.World.Entity.Player.Instances

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid} = state) do
    Instances.reset(guid)
    state
  end

  def handle(%__MODULE__{}, state), do: state
end
