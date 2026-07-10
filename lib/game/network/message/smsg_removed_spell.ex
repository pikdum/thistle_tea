defmodule ThistleTea.Game.Network.Message.SmsgRemovedSpell do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_REMOVED_SPELL

  defstruct [:spell_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{spell_id: spell_id}) do
    <<spell_id::little-size(16)>>
  end
end
