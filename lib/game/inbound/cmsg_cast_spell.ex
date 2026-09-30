defmodule ThistleTea.Game.Inbound.CmsgCastSpell do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CAST_SPELL

  alias ThistleTea.Game.World.Entity.Player.Spellcasting

  defstruct [:spell_id, :spell_cast_targets]

  @impl ClientMessage
  def from_binary(payload) do
    <<spell_id::little-size(32), spell_cast_targets::binary>> = payload

    %__MODULE__{
      spell_id: spell_id,
      spell_cast_targets: spell_cast_targets
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{spell_id: spell_id, spell_cast_targets: spell_cast_targets}, state) do
    Spellcasting.cast(state, spell_id, spell_cast_targets)
  end
end
