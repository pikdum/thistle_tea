defmodule ThistleTea.Game.Network.Message.SmsgLearnedSpell do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LEARNED_SPELL

  defstruct [:spell_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{spell_id: spell_id}) do
    <<spell_id::little-size(32)>>
  end
end
