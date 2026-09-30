defmodule ThistleTea.Game.Inbound.CmsgCancelGrowthAura do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CANCEL_GROWTH_AURA

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: state
end
