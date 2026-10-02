defmodule ThistleTea.Game.Inbound.CmsgToggleCloak do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_TOGGLE_CLOAK

  alias ThistleTea.Game.World.Entity.Player.Appearance

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Appearance.toggle_hidden(state, :cloak)
end
