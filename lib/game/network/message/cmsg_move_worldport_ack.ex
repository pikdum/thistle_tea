defmodule ThistleTea.Game.Network.Message.CmsgMoveWorldportAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_WORLDPORT_ACK

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.Player.Login
  alias ThistleTea.Game.World.Visibility

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Login.send_init_packets(state.character)

    state = State.complete_worldport(state)
    state = Visibility.enter_player(%{state | ready: true})
    send(self(), :restore_companion)
    PlayerExploration.check_current(state)
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
