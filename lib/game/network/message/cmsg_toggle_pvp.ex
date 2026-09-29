defmodule ThistleTea.Game.Network.Message.CmsgTogglePvp do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TOGGLE_PVP

  defstruct [:enabled]

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{enabled: :toggle}
  def from_binary(<<enabled::8>>) when enabled in [0, 1], do: %__MODULE__{enabled: enabled == 1}
  def from_binary(_payload), do: %__MODULE__{}
end
