defmodule ThistleTea.Game.Network.Message.SmsgSpellheallog do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELLHEALLOG

  defstruct [:target, :caster, :spell_id, :amount, critical?: false]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    BinaryUtils.pack_guid(message.target) <>
      BinaryUtils.pack_guid(message.caster) <>
      <<message.spell_id::little-size(32), message.amount::little-size(32),
        if(message.critical?, do: 1, else: 0)::little-size(8)>>
  end
end
