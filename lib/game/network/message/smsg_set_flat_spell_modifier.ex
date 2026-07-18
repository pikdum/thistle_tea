defmodule ThistleTea.Game.Network.Message.SmsgSetFlatSpellModifier do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SET_FLAT_SPELL_MODIFIER

  defstruct [:effect_index, :operation, :value]

  @impl ServerMessage
  def to_binary(%__MODULE__{effect_index: effect_index, operation: operation, value: value}) do
    <<effect_index::size(8), operation::size(8), value::little-signed-size(32)>>
  end
end
