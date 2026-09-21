defmodule ThistleTea.Game.Network.Message.CmsgLogoutCancel do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOGOUT_CANCEL

  alias ThistleTea.Game.Player.Logout

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_LOGOUT_CANCEL")

    Logout.cancel(state)
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
