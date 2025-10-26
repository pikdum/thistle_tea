defmodule ThistleTea.Game.Message.CmsgLogoutCancel do
  use ThistleTea.Game.ClientMessage, :CMSG_LOGOUT_CANCEL

  alias ThistleTea.Game.Message
  alias ThistleTea.Util

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_LOGOUT_CANCEL")

    state =
      case Map.get(state, :logout_timer, nil) do
        nil ->
          state

        timer ->
          Process.cancel_timer(timer)
          Map.delete(state, :logout_timer)
      end

    Util.send_packet(%Message.SmsgLogoutCancelAck{})
    state
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
