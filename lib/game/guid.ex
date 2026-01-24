defmodule ThistleTea.Game.Guid do
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

  defp type_id_from_high(high_guid) do
    case high_guid do
      @high_guid_item -> :item
      @high_guid_unit -> :unit
      @high_guid_pet -> :unit
      @high_guid_player -> :player
      @high_guid_game_object -> :game_object
      @high_guid_dynamic_object -> :dynamic_object
      @high_guid_corpse -> :corpse
      @high_guid_mo_transport -> :game_object
      _ -> :object
    end
  end

  defp has_entry?(high_guid) do
    high_guid not in @entryless_high_guids
  end
end
