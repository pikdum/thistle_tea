defmodule ThistleTea.Game.Network.Message.CmsgLogoutRequest do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOGOUT_REQUEST

  alias ThistleTea.Game.Player.Logout

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_LOGOUT_REQUEST")
    Logout.request(state)
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
