defmodule ThistleTea.Game.Network.Message.CmsgRequestPetInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REQUEST_PET_INFO

  alias ThistleTea.Game.Player.Login

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{}} = state) do
    Login.refresh_companion(state)
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
