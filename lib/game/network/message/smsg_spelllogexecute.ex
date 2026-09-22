defmodule ThistleTea.Game.Network.Message.SmsgSpelllogexecute do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELLLOGEXECUTE

  defstruct [:caster, :spell_id, logs: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{caster: caster, spell_id: spell_id, logs: logs}) do
    BinaryUtils.pack_guid(caster) <>
      <<spell_id::little-size(32), length(logs)::little-size(32)>> <>
      Enum.map_join(logs, &encode_log/1)
  end

  defp encode_log({:extra_attacks, target, count}) do
    <<19::little-size(32), 1::little-size(32), target::little-size(64), count::little-size(32)>>
  end
end
