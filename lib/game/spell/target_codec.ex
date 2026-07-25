defmodule ThistleTea.Game.Spell.TargetCodec do
  @moduledoc """
  Encodes and decodes the spell-target wire format.
  """
  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Spell.Target

  @self 0x00000000
  @unit 0x00000002
  @item 0x00000010
  @source_location 0x00000020
  @destination_location 0x00000040
  @object 0x00000800
  @object_locked 0x00004000
  @corpse 0x00008000

  def parse(<<flags::little-size(16), rest::binary>>, caster_guid) do
    target =
      if flags == @self do
        Target.self(caster_guid)
      else
        Target.none()
      end

    {_rest, target} =
      [
        {@unit, &parse_unit/2},
        {@item, &parse_item/2},
        {@object, &parse_object/2},
        {@object_locked, &parse_locked_object/2},
        {@source_location, &parse_source_location/2},
        {@destination_location, &parse_destination_location/2},
        {@corpse, &parse_corpse/2}
      ]
      |> Enum.reduce({rest, target}, fn
        {mask, parse}, {rest, target} when (flags &&& mask) > 0 -> parse.(rest, target)
        _field, result -> result
      end)

    target
  end

  def parse(_payload, caster_guid), do: Target.self(caster_guid)

  def encode(%Target{} = target) do
    {selection_flag, selection_prefix, selection_suffix} = encode_selection(target.selection)
    {source_flag, source_binary} = encode_location(target.source_location, @source_location)
    {destination_flag, destination_binary} = encode_location(target.destination_location, @destination_location)
    flags = selection_flag ||| source_flag ||| destination_flag

    <<flags::little-size(16)>> <>
      selection_prefix <>
      source_binary <>
      destination_binary <>
      selection_suffix
  end

  defp parse_unit(rest, target), do: parse_guid(rest, target, &%{&1 | selection: {:unit, &2}})
  defp parse_item(rest, target), do: parse_guid(rest, target, &%{&1 | selection: {:item, &2}})
  defp parse_object(rest, target), do: parse_guid(rest, target, &%{&1 | selection: {:object, &2, :open}})
  defp parse_locked_object(rest, target), do: parse_guid(rest, target, &%{&1 | selection: {:object, &2, :locked}})

  defp parse_source_location(rest, target) do
    parse_location(rest, target, &%{&1 | source_location: &2})
  end

  defp parse_destination_location(rest, target) do
    parse_location(rest, target, &%{&1 | destination_location: &2})
  end

  defp parse_corpse(rest, target) do
    parse_guid(rest, target, fn target, corpse_guid ->
      player_guid = Guid.from_low_guid(:player, Guid.low_guid(corpse_guid))
      %{target | selection: {:corpse, corpse_guid, player_guid}}
    end)
  end

  defp parse_guid(rest, target, put) do
    case unpack_guid(rest) do
      {guid, rest} -> {rest, put.(target, guid)}
      :error -> {rest, target}
    end
  end

  defp parse_location(
         <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32), rest::binary>>,
         target,
         put
       ) do
    {rest, put.(target, {x, y, z})}
  end

  defp parse_location(rest, target, _put), do: {rest, target}

  defp unpack_guid(rest) do
    BinaryUtils.unpack_guid(rest)
  rescue
    _ -> :error
  end

  defp encode_selection(:none), do: {@self, <<>>, <<>>}
  defp encode_selection({:self, _guid}), do: {@self, <<>>, <<>>}
  defp encode_selection({:unit, guid}), do: {@unit, BinaryUtils.pack_guid(guid), <<>>}
  defp encode_selection({:item, guid}), do: {@item, BinaryUtils.pack_guid(guid), <<>>}
  defp encode_selection({:object, guid, :open}), do: {@object, BinaryUtils.pack_guid(guid), <<>>}
  defp encode_selection({:object, guid, :locked}), do: {@object_locked, BinaryUtils.pack_guid(guid), <<>>}
  defp encode_selection({:corpse, guid, _player_guid}), do: {@corpse, <<>>, BinaryUtils.pack_guid(guid)}

  defp encode_location(nil, _flag), do: {@self, <<>>}

  defp encode_location({x, y, z}, flag) do
    {flag, <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32)>>}
  end
end
