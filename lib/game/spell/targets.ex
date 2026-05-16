defmodule ThistleTea.Game.Spell.Targets do
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Network.BinaryUtils

  @self 0x00000000
  @unit 0x00000002
  @source_location 0x00000020
  @destination_location 0x00000040

  defstruct [
    :flags,
    :raw,
    :unit_guid,
    :source_location,
    :destination_location
  ]

  def parse(payload, caster_guid) when is_binary(payload) do
    <<flags::little-size(16), rest::binary>> = payload

    %__MODULE__{flags: flags, raw: payload}
    |> put_self_target(caster_guid)
    |> parse_unit(rest)
    |> parse_locations(rest)
  end

  def parse(_payload, caster_guid) do
    %__MODULE__{flags: @self, raw: <<@self::little-size(16)>>, unit_guid: caster_guid}
  end

  defp put_self_target(%__MODULE__{flags: @self} = targets, caster_guid) do
    %{targets | unit_guid: caster_guid}
  end

  defp put_self_target(targets, _caster_guid), do: targets

  defp parse_unit(%__MODULE__{flags: flags} = targets, rest) when (flags &&& @unit) > 0 do
    {guid, _rest} = BinaryUtils.unpack_guid(rest)
    %{targets | unit_guid: guid}
  end

  defp parse_unit(targets, _rest), do: targets

  defp parse_locations(%__MODULE__{flags: flags} = targets, rest) do
    {_rest, targets} =
      [
        {@unit, :unit_guid},
        {@source_location, :source_location},
        {@destination_location, :destination_location}
      ]
      |> Enum.reduce({rest, targets}, fn
        {@unit, _field}, {rest, acc} when (flags &&& @unit) > 0 ->
          {_guid, rest} = BinaryUtils.unpack_guid(rest)
          {rest, acc}

        {mask, field}, {rest, acc} when (flags &&& mask) > 0 ->
          parse_location(rest, acc, field)

        _entry, result ->
          result
      end)

    targets
  end

  defp parse_location(rest, targets, field) do
    case rest do
      <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32), rest::binary>> ->
        {rest, Map.put(targets, field, {x, y, z})}

      _ ->
        {rest, targets}
    end
  end
end
