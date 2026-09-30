defmodule ThistleTea.Game.Inbound.CmsgRequestPetInfo do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_REQUEST_PET_INFO

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Login

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{}} = state) do
    Login.refresh_companion(state)
  end

  def handle(%__MODULE__{}, state), do: state
end
