defmodule ThistleTea.Game.Inbound.MsgLookingForGroup do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_LOOKING_FOR_GROUP

  alias ThistleTea.Game.World.Outbound

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid} = state) do
    Outbound.send_packet(%Message.MsgLookingForGroup{}, guid)
    state
  end

  def handle(%__MODULE__{}, state), do: state
end
