defmodule ThistleTea.Game.Inbound.CmsgLogoutRequest do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_LOGOUT_REQUEST, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Logout

  require Logger

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_LOGOUT_REQUEST")
    Logout.request(state)
  end
end
