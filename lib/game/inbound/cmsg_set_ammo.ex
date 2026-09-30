defmodule ThistleTea.Game.Inbound.CmsgSetAmmo do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SET_AMMO

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Ammunition

  defstruct [:item]

  @impl ClientMessage
  def from_binary(<<item::little-size(32)>>), do: %__MODULE__{item: item}

  @impl ClientMessage
  def handle(%__MODULE__{item: item}, %{ready: true, character: %Character{}} = state),
    do: Ammunition.select(state, item)

  def handle(%__MODULE__{}, state), do: state
end
