defmodule ThistleTea.Game.Network.Message.CmsgCancelGrowthAura do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_GROWTH_AURA

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
