defmodule ThistleTea.Game.Network.Message.CmsgCancelAura do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_AURA

  defstruct [:spell_id]

  @impl ClientMessage
  def from_binary(<<spell_id::little-size(32), _rest::binary>>), do: %__MODULE__{spell_id: spell_id}
  def from_binary(_payload), do: %__MODULE__{}
end
