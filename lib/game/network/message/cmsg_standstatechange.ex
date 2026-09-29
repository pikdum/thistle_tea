defmodule ThistleTea.Game.Network.Message.CmsgStandstatechange do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_STANDSTATECHANGE

  defstruct [:animation_state]

  @impl ClientMessage
  def from_binary(<<animation_state::little-size(32)>>), do: %__MODULE__{animation_state: animation_state}
end
