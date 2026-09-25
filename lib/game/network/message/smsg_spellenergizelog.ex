defmodule ThistleTea.Game.Network.Message.SmsgSpellenergizelog do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELLENERGIZELOG

  defstruct [:target, :caster, :spell_id, :power_type, :amount]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    BinaryUtils.pack_guid(message.target) <>
      BinaryUtils.pack_guid(message.caster) <>
      <<message.spell_id::little-size(32), message.power_type::little-size(32), message.amount::little-size(32)>>
  end
end
