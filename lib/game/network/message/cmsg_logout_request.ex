defmodule ThistleTea.Game.Network.Message.CmsgLogoutRequest do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOGOUT_REQUEST

  alias ThistleTea.Game.Network.Message

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_LOGOUT_REQUEST")
    Network.send_packet(%Message.SmsgLogoutResponse{result: 0, speed: 0})
    logout_timer = Process.send_after(self(), :logout_complete, 1_000)
    %{state | logout_timer: logout_timer}
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
