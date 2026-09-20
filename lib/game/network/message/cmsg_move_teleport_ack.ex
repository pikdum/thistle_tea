defmodule ThistleTea.Game.Network.Message.CmsgMoveTeleportAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_TELEPORT_ACK

  alias ThistleTea.Game.Player.Travel

  defstruct [:guid, :counter, :time]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, counter: counter}, %{guid: guid} = state) do
    Travel.teleport_ack(state, guid, counter)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), counter::little-size(32), time::little-size(32), _rest::binary>> = payload

    %__MODULE__{
      guid: guid,
      counter: counter,
      time: time
    }
  end
end
