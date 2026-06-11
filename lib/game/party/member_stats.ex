defmodule ThistleTea.Game.Party.MemberStats do
  @moduledoc """
  Builds SMSG_PARTY_MEMBER_STATS field sets from a character and encodes the
  packed-guid + update-flag-mask wire format shared by the incremental and
  full variants.
  """
  import Bitwise

  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Network.BinaryUtils

  @status_online 0x01
  @status_dead 0x04
  @status_ghost 0x08

  @fields [
    {0x00000001, :status, :u8},
    {0x00000002, :cur_hp, :u16},
    {0x00000004, :max_hp, :u16},
    {0x00000008, :power_type, :u8},
    {0x00000010, :cur_power, :u16},
    {0x00000020, :max_power, :u16},
    {0x00000040, :level, :u16},
    {0x00000080, :zone, :u16}
  ]

  def from_character(character) do
    power_type = character.unit.power_type || 0

    %{
      guid: character.object.guid,
      status: status(character),
      cur_hp: character.unit.health,
      max_hp: character.unit.max_health,
      power_type: power_type,
      cur_power: power_value(character.unit, power_type),
      max_power: power_value(character.unit, power_type, "max_power"),
      level: character.unit.level,
      zone: character.internal.area
    }
  end

  def offline(guid), do: %{guid: guid, status: 0}

  def encode(stats) do
    {mask, payload} =
      Enum.reduce(@fields, {0, <<>>}, fn {flag, key, type}, {mask, payload} ->
        case Map.get(stats, key) do
          nil -> {mask, payload}
          value -> {mask ||| flag, payload <> encode_field(value, type)}
        end
      end)

    BinaryUtils.pack_guid(Map.fetch!(stats, :guid)) <> <<mask::little-size(32)>> <> payload
  end

  defp status(character) do
    @status_online
    |> set_flag(@status_dead, not Death.alive?(character))
    |> set_flag(@status_ghost, Death.ghost?(character))
  end

  defp set_flag(status, flag, true), do: status ||| flag
  defp set_flag(status, _flag, false), do: status

  defp power_value(unit, power_type, prefix \\ "power") do
    case Map.get(unit, String.to_existing_atom("#{prefix}#{power_type + 1}")) do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  defp encode_field(value, :u8), do: <<clamp(value, 0xFF)::little-size(8)>>
  defp encode_field(value, :u16), do: <<clamp(value, 0xFFFF)::little-size(16)>>

  defp clamp(value, limit) when is_integer(value), do: value |> max(0) |> min(limit)
  defp clamp(_value, _limit), do: 0
end
