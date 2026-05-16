defmodule ThistleTea.Game.Network.Message.SmsgSpellNonMeleeDamageLog do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELLNONMELEEDAMAGELOG

  defstruct attacker: 0,
            target: 0,
            spell_id: 0,
            damage: 0,
            school: 0,
            absorbed: 0,
            resisted: 0,
            blocked: 0,
            periodic?: false,
            hit_info: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    BinaryUtils.pack_guid(message.target) <>
      BinaryUtils.pack_guid(message.attacker) <>
      <<
        message.spell_id::little-size(32),
        message.damage::little-size(32),
        message.school::little-size(8),
        message.absorbed::little-size(32),
        message.resisted::little-signed-size(32),
        bool_byte(message.periodic?)::little-size(8),
        0::little-size(8),
        message.blocked::little-size(32),
        message.hit_info::little-size(32),
        0::little-size(8)
      >>
  end

  defp bool_byte(true), do: 1
  defp bool_byte(_), do: 0
end
