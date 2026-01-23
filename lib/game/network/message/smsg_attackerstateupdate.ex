defmodule ThistleTea.Game.Network.Message.SmsgAttackerstateupdate do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ATTACKERSTATEUPDATE

  @default_hit_info 0x00000002

  defstruct hit_info: @default_hit_info,
            attacker: 0,
            target: 0,
            total_damage: 0,
            damages: [],
            damage_state: 0,
            unknown1: 0,
            spell_id: 0,
            blocked_amount: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    total_damage = normalize_integer(message.total_damage)
    attacker = normalize_integer(message.attacker)
    target = normalize_integer(message.target)
    damages = normalize_damages(total_damage, message.damages)
    amount_of_damages = length(damages)

    <<message.hit_info::little-size(32)>> <>
      BinaryUtils.pack_guid(attacker) <>
      BinaryUtils.pack_guid(target) <>
      <<total_damage::little-size(32), amount_of_damages::little-size(8)>> <>
      Enum.map_join(damages, "", &damage_binary/1) <>
      <<
        message.damage_state::little-size(32),
        message.unknown1::little-size(32),
        message.spell_id::little-size(32),
        message.blocked_amount::little-size(32)
      >>
  end

  defp normalize_damages(_total_damage, damages) when is_list(damages) and damages != [] do
    damages
  end

  defp normalize_damages(total_damage, _damages) do
    [default_damage(total_damage)]
  end

  defp default_damage(total_damage) when is_number(total_damage) do
    total_damage = trunc(total_damage)

    %{
      spell_school_mask: 0,
      damage_float: total_damage * 1.0,
      damage_uint: total_damage,
      absorb: 0,
      resist: 0
    }
  end

  defp default_damage(_total_damage) do
    %{
      spell_school_mask: 0,
      damage_float: 0.0,
      damage_uint: 0,
      absorb: 0,
      resist: 0
    }
  end

  defp damage_binary(damage) do
    spell_school_mask = Map.get(damage, :spell_school_mask, 0)
    damage_float = normalize_float(Map.get(damage, :damage_float, 0.0))
    damage_uint = Map.get(damage, :damage_uint, trunc(damage_float))
    absorb = Map.get(damage, :absorb, 0)
    resist = Map.get(damage, :resist, 0)

    <<
      spell_school_mask::little-size(32),
      damage_float::little-float-size(32),
      damage_uint::little-size(32),
      absorb::little-size(32),
      resist::little-size(32)
    >>
  end

  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(value) when is_float(value), do: trunc(value)
  defp normalize_integer(_value), do: 0

  defp normalize_float(value) when is_float(value), do: value
  defp normalize_float(value) when is_integer(value), do: value * 1.0
  defp normalize_float(_value), do: 0.0
end
