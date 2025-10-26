defmodule ThistleTea.Game.Message.CmsgMoveWorldportAck do
  use ThistleTea.Game.ClientMessage, :MSG_MOVE_WORLDPORT_ACK

  alias ThistleTea.Game.Message.CmsgPlayerLogin

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    CmsgPlayerLogin.send_login_init_packets(state.character)
    %{state | ready: true}
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
