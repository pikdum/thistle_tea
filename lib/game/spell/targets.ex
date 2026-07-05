defmodule ThistleTea.Game.Spell.Targets do
  @moduledoc """
  The spell-cast targets blob from CMSG_CAST_SPELL: parses target flags into
  unit guid and source/destination locations, and keeps the raw binary for
  echoing back in SMSG_SPELL_GO.
  """
  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils

  @self 0x00000000
  @unit 0x00000002
  @object 0x00000800
  @object_locked 0x00004000
  @source_location 0x00000020
  @destination_location 0x00000040
  @corpse 0x00008000

  defstruct [
    :flags,
    :raw,
    :unit_guid,
    :object_guid,
    :source_location,
    :destination_location
  ]

  def parse(<<flags::little-size(16), rest::binary>> = payload, caster_guid) do
    %__MODULE__{flags: flags, raw: payload}
    |> put_self_target(caster_guid)
    |> parse_fields(rest)
  end

  def parse(_payload, caster_guid) do
    self_target(caster_guid)
  end

  def unit(guid) when is_integer(guid) and guid > 0 do
    %__MODULE__{
      flags: @unit,
      raw: <<@unit::little-size(16)>> <> BinaryUtils.pack_guid(guid),
      unit_guid: guid
    }
  end

  def ground_location(%__MODULE__{destination_location: location}) when is_tuple(location), do: location
  def ground_location(%__MODULE__{source_location: location}) when is_tuple(location), do: location
  def ground_location(_targets), do: nil

  defp put_self_target(%__MODULE__{flags: @self} = targets, caster_guid) do
    %{targets | unit_guid: caster_guid}
  end

  defp put_self_target(targets, _caster_guid), do: targets

  defp self_target(caster_guid) do
    %__MODULE__{flags: @self, raw: <<@self::little-size(16)>>, unit_guid: caster_guid}
  end

  defp parse_fields(%__MODULE__{flags: flags} = targets, rest) do
    {_rest, targets} =
      [
        {@unit, :unit_guid},
        {@object ||| @object_locked, :object_guid},
        {@source_location, :source_location},
        {@destination_location, :destination_location},
        {@corpse, :corpse}
      ]
      |> Enum.reduce({rest, targets}, fn
        {@unit, :unit_guid}, {rest, acc} when (flags &&& @unit) > 0 ->
          parse_guid_field(rest, acc, :unit_guid)

        {mask, :object_guid}, {rest, acc} when (flags &&& mask) > 0 ->
          parse_guid_field(rest, acc, :object_guid)

        {@corpse, :corpse}, {rest, acc} when (flags &&& @corpse) > 0 ->
          parse_corpse(rest, acc)

        {mask, field}, {rest, acc} when (flags &&& mask) > 0 ->
          parse_location(rest, acc, field)

        _entry, result ->
          result
      end)

    targets
  end

  defp parse_guid_field(rest, targets, field) do
    case unpack_guid(rest) do
      {guid, rest} -> {rest, Map.replace!(targets, field, guid)}
      :error -> {rest, targets}
    end
  end

  defp parse_corpse(rest, targets) do
    case unpack_guid(rest) do
      {corpse_guid, rest} ->
        {rest, %{targets | unit_guid: Guid.from_low_guid(:player, Guid.low_guid(corpse_guid))}}

      :error ->
        {rest, targets}
    end
  end

  defp parse_location(rest, targets, field) do
    case rest do
      <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32), rest::binary>> ->
        {rest, Map.put(targets, field, {x, y, z})}

      _ ->
        {rest, targets}
    end
  end

  defp unpack_guid(rest) do
    BinaryUtils.unpack_guid(rest)
  rescue
    _ -> :error
  end
end
