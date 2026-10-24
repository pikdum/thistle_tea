defmodule ThistleTea.Game.Core.Guid do
  @moduledoc """
  Guid construction and inspection: high-guid prefixes per entity type,
  counter allocation, and mapping guids back to entity/type ids.
  """
  import Bitwise, only: [&&&: 2, <<<: 2, >>>: 2, |||: 2]

  @high_guid_item 0x4000
  @high_guid_container 0x4000
  @high_guid_player 0x0000
  @high_guid_game_object 0xF110
  @high_guid_transport 0xF120
  @high_guid_unit 0xF130
  @high_guid_pet 0xF140
  @high_guid_dynamic_object 0xF100
  @high_guid_corpse 0xF101
  @high_guid_mo_transport 0x1FC0

  @entryless_high_guids [
    @high_guid_item,
    @high_guid_player,
    @high_guid_dynamic_object,
    @high_guid_corpse,
    @high_guid_mo_transport
  ]

  @entryless_types [:item, :container, :player, :dynamic_object, :corpse, :mo_transport]
  @entry_types [:game_object, :transport, :unit, :pet, :mob, :creature]
  @runtime_low_guid_base 0xC00000
  @runtime_low_guid_count 0x3FFFFF

  def high_guid(:mob), do: @high_guid_unit
  def high_guid(:unit), do: @high_guid_unit
  def high_guid(:creature), do: @high_guid_unit
  def high_guid(:item), do: @high_guid_item
  def high_guid(:container), do: @high_guid_container
  def high_guid(:player), do: @high_guid_player
  def high_guid(:game_object), do: @high_guid_game_object
  def high_guid(:transport), do: @high_guid_transport
  def high_guid(:pet), do: @high_guid_pet
  def high_guid(:dynamic_object), do: @high_guid_dynamic_object
  def high_guid(:corpse), do: @high_guid_corpse
  def high_guid(:mo_transport), do: @high_guid_mo_transport
  def high_guid(guid) when is_integer(guid), do: guid >>> 48 &&& 0xFFFF

  def from_low_guid(type, low_guid) when type in @entryless_types and is_integer(low_guid) do
    high = high_guid(type)

    if low_guid == 0 do
      0
    else
      high <<< 48 ||| low_guid
    end
  end

  def from_low_guid(type, entry, low_guid) when type in @entry_types and is_integer(entry) and is_integer(low_guid) do
    high = high_guid(type)

    if low_guid == 0 do
      0
    else
      high <<< 48 ||| entry <<< 24 ||| low_guid
    end
  end

  def runtime(type, entry) when type in @entry_types and is_integer(entry) do
    low_guid = @runtime_low_guid_base + rem(:erlang.unique_integer([:positive, :monotonic]), @runtime_low_guid_count)
    from_low_guid(type, entry, low_guid)
  end

  def split(guid) when is_integer(guid) do
    {high_guid(guid), low_guid(guid)}
  end

  def low_guid(guid) when is_integer(guid) do
    high = high_guid(guid)

    cond do
      guid == 0 -> 0
      has_entry?(high) -> guid &&& 0x00FFFFFF
      true -> guid &&& 0xFFFFFFFF
    end
  end

  def entry(guid) when is_integer(guid) do
    high = high_guid(guid)

    cond do
      guid == 0 -> 0
      has_entry?(high) -> guid >>> 24 &&& 0x00FFFFFF
      true -> 0
    end
  end

  def type_id(guid) when is_integer(guid) do
    case guid do
      0 -> :object
      _ -> type_id_from_high(high_guid(guid))
    end
  end

  def entity_type(guid) when is_integer(guid) and guid > 0 do
    case type_id(guid) do
      :unit -> :mob
      :object -> :object
      type -> type
    end
  end

  def entity_type(_), do: nil

  def transport?(guid) when is_integer(guid) do
    high_guid(guid) in [@high_guid_transport, @high_guid_mo_transport]
  end

  def transport?(_guid), do: false

  def pack(guid) when is_integer(guid), do: pack_bytes(<<guid::64>>)
  def pack(<<_::64>> = guid), do: pack_bytes(guid)

  defp pack_bytes(<<b7, b6, b5, b4, b3, b2, b1, b0>>) do
    <<present(b7)::1, present(b6)::1, present(b5)::1, present(b4)::1, present(b3)::1, present(b2)::1, present(b1)::1,
      present(b0)::1, packed(b0)::binary, packed(b1)::binary, packed(b2)::binary, packed(b3)::binary,
      packed(b4)::binary, packed(b5)::binary, packed(b6)::binary, packed(b7)::binary>>
  end

  def unpack(<<m7::1, m6::1, m5::1, m4::1, m3::1, m2::1, m1::1, m0::1, rest::binary>>) do
    {b0, rest} = take_byte(m0, rest)
    {b1, rest} = take_byte(m1, rest)
    {b2, rest} = take_byte(m2, rest)
    {b3, rest} = take_byte(m3, rest)
    {b4, rest} = take_byte(m4, rest)
    {b5, rest} = take_byte(m5, rest)
    {b6, rest} = take_byte(m6, rest)
    {b7, rest} = take_byte(m7, rest)
    <<guid::64>> = <<b7, b6, b5, b4, b3, b2, b1, b0>>
    {guid, rest}
  end

  defp present(0), do: 0
  defp present(_byte), do: 1

  defp packed(0), do: <<>>
  defp packed(byte), do: <<byte>>

  defp take_byte(0, rest), do: {0, rest}
  defp take_byte(1, <<byte, rest::binary>>), do: {byte, rest}

  defp type_id_from_high(@high_guid_item), do: :item
  defp type_id_from_high(@high_guid_unit), do: :unit
  defp type_id_from_high(@high_guid_pet), do: :unit
  defp type_id_from_high(@high_guid_player), do: :player
  defp type_id_from_high(@high_guid_game_object), do: :game_object
  defp type_id_from_high(@high_guid_transport), do: :game_object
  defp type_id_from_high(@high_guid_dynamic_object), do: :dynamic_object
  defp type_id_from_high(@high_guid_corpse), do: :corpse
  defp type_id_from_high(@high_guid_mo_transport), do: :game_object
  defp type_id_from_high(_high_guid), do: :object

  defp has_entry?(high_guid) do
    high_guid not in @entryless_high_guids
  end
end
