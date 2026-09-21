defmodule ThistleTea.Game.Network.Message.CmsgSetAmmo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_AMMO

  alias ThistleTea.Game.Player.Ammunition

  defstruct [:item]

  @impl ClientMessage
  def from_binary(<<item::little-size(32)>>), do: %__MODULE__{item: item}

  @impl ClientMessage
  def handle(%__MODULE__{item: item}, %{ready: true, character: %Character{}} = state),
    do: Ammunition.select(state, item)

  def handle(_message, state), do: state
end
