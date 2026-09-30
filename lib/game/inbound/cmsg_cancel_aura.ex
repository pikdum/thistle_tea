defmodule ThistleTea.Game.Inbound.CmsgCancelAura do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CANCEL_AURA

  alias ThistleTea.Game.World.Entity.Player.Spells

  defstruct [:spell_id]

  @impl ClientMessage
  def from_binary(<<spell_id::little-size(32), _rest::binary>>), do: %__MODULE__{spell_id: spell_id}
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{spell_id: spell_id}, state), do: Spells.cancel_aura(state, spell_id)
end
