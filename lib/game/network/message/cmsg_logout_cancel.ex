defmodule ThistleTea.Game.Network.Message.CmsgLogoutCancel do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOGOUT_CANCEL

  alias ThistleTea.Game.Network.Message

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_LOGOUT_CANCEL")

    state =
      case Map.get(state, :logout_timer) do
        nil ->
          state

        timer ->
          Process.cancel_timer(timer)
          %{state | logout_timer: nil}
      end

    Network.send_packet(%Message.SmsgLogoutCancelAck{})
    state
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
