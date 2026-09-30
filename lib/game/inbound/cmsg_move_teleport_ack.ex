defmodule ThistleTea.Game.Inbound.CmsgMoveTeleportAck do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_MOVE_TELEPORT_ACK

  alias ThistleTea.Game.World.Entity.Player.Travel

  defstruct [:guid, :counter, :time]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), counter::little-size(32), time::little-size(32), _rest::binary>> = payload

    %__MODULE__{
      guid: guid,
      counter: counter,
      time: time
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, counter: counter}, %{guid: guid} = state) do
    Travel.teleport_ack(state, guid, counter)
  end

  def handle(%__MODULE__{}, state), do: state
end
