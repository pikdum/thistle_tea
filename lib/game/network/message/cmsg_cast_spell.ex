defmodule ThistleTea.Game.Network.Message.CmsgCastSpell do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CAST_SPELL

  alias ThistleTea.Game.Player.Spellcasting

  defstruct [:spell_id, :spell_cast_targets]

  @impl ClientMessage
  def handle(%__MODULE__{spell_id: spell_id, spell_cast_targets: spell_cast_targets}, state) do
    Spellcasting.cast(state, spell_id, spell_cast_targets)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<spell_id::little-size(32), spell_cast_targets::binary>> = payload

    %__MODULE__{
      spell_id: spell_id,
      spell_cast_targets: spell_cast_targets
    }
  end
end
