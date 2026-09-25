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

  defp encode_log({:power_drain, target, amount, power, multiplier}) do
    <<8::little-size(32), 1::little-size(32), target::little-size(64), amount::little-size(32), power::little-size(32),
      multiplier::little-float-size(32)>>
  end

  defp encode_log({:interrupt_cast, target, interrupted_spell}) do
    <<68::little-size(32), 1::little-size(32), target::little-size(64), interrupted_spell::little-size(32)>>
  end

  defp encode_log({:durability_damage, target, item_entry}) do
    <<111::little-size(32), 1::little-size(32), target::little-size(64), item_entry::little-size(32),
      -1::little-size(32)>>
  end
end
