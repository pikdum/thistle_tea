defmodule ThistleTea.Game.Network.Message.SmsgSupercededSpell do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SUPERCEDED_SPELL

  defstruct [:old_spell_id, :new_spell_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{old_spell_id: old_spell_id, new_spell_id: new_spell_id}) do
    <<old_spell_id::little-size(16), new_spell_id::little-size(16)>>
  end
end
