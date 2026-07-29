defmodule ThistleTea.Game.Network.Message.CmsgMoveWorldportAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_WORLDPORT_ACK

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.CompanionVisibility
  alias ThistleTea.Game.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.Player.Login
  alias ThistleTea.Game.World.Visibility

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Login.send_worldport_packets(state.character)

    state = State.complete_worldport(state)
    state = Visibility.enter_player(%{state | ready: true})

    state
    |> CompanionVisibility.defer_restoration()
    |> PlayerExploration.check_current()
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
