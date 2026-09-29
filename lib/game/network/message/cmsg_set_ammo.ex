defmodule ThistleTea.Game.Network.Message.CmsgSetAmmo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_AMMO

  defstruct [:item]

  @impl ClientMessage
  def from_binary(<<item::little-size(32)>>), do: %__MODULE__{item: item}
end
