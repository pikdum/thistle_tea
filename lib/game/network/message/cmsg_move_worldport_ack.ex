defmodule ThistleTea.Game.Network.Message.CmsgMoveWorldportAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_WORLDPORT_ACK

  alias ThistleTea.Game.Player.Login
  alias ThistleTea.Game.World.Visibility

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Login.send_init_packets(state.character)

    state = Visibility.enter_player(%{state | ready: true})
    send(self(), :restore_active_pet)
    state
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
