defmodule ThistleTea.Game.Network.UpdateObject do
  @moduledoc """
  Builds SMSG_UPDATE_OBJECT blocks: flattens component field structs into
  field values, generates the update mask, and encodes create/values blocks.

  The vanilla client only accepts one leading out-of-range block. Batches
  merge removals there and discard earlier updates for removed objects.
  """
  use ThistleTea.Game.Network.Opcodes, [:SMSG_UPDATE_OBJECT]

  import Bitwise, only: [|||: 2, <<<: 2]

  alias ThistleTea.Game.Core.Combat.Assistance
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Corpse
  alias ThistleTea.Game.Core.Entity.DynamicObject
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Item, as: ItemCore
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Empathy
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Packet

  defstruct [
    :update_type,
    :out_of_range_guids,
    :has_transport,
    :object_type,
    :movement_block,
    :object,
    :item,
    :container,
    :unit,
    :player,
    :game_object,
    :dynamic_object,
    :corpse
  ]

  # TODO: would be neat to have a module to define flags + enums
  # or one module per enum/flag set?

  @update_type_values 0
  @update_type_create_object 2
  @update_type_create_object2 3
  @update_type_out_of_range_objects 4

  defp update_type(:create_object), do: @update_type_create_object
  defp update_type(:create_object2), do: @update_type_create_object2

  @object_type_object 0x00
  @object_type_item 0x01
  @object_type_container 0x02
  @object_type_unit 0x03
  @object_type_player 0x04
  @object_type_game_object 0x05
  @object_type_dynamic_object 0x06
  @object_type_corpse 0x07

  defp object_type(:object), do: @object_type_object
  defp object_type(:item), do: @object_type_item
  defp object_type(:container), do: @object_type_container
  defp object_type(:unit), do: @object_type_unit
  defp object_type(:player), do: @object_type_player
  defp object_type(:game_object), do: @object_type_game_object
  defp object_type(:dynamic_object), do: @object_type_dynamic_object
  defp object_type(:corpse), do: @object_type_corpse

  @object_type_flags_map %{
    object: 0x01,
    item: 0x02,
    container: 0x04,
    unit: 0x08,
    player: 0x10,
    game_object: 0x20,
    dynamic_object: 0x40,
    corpse: 0x80
  }

  def from_entity(entity, update_type \\ :create_object2)

  def from_entity(%Mob{} = entity, update_type) do
    entity = %{entity | unit: %{entity.unit | target: Assistance.visible_target(entity)}}
    from_entity(entity, update_type, :unit)
  end

  def from_entity(%GameObject{} = entity, update_type), do: from_entity(entity, update_type, :game_object)
  def from_entity(%Corpse{} = entity, update_type), do: from_entity(entity, update_type, :corpse)
  def from_entity(%DynamicObject{} = entity, update_type), do: from_entity(entity, update_type, :dynamic_object)
  def from_entity(%Character{} = entity, update_type), do: from_entity(entity, update_type, :player)

  def from_entity(entity, update_type, object_type) do
    struct(%__MODULE__{update_type: update_type, object_type: object_type}, Map.from_struct(entity))
  end

  def mask_blocks_count(fields), do: fields |> highest_bit() |> mask_count()

  def highest_bit(fields) do
    fields
    |> Enum.map(fn {_key, _value, {offset, size, _type}} -> offset + size - 1 end)
    |> Enum.max(fn -> 0 end)
  end

  def generate_mask(fields) do
    {mask_count, mask, _data} = encode_fields(fields)
    mask_binary(mask_count, mask)
  end

  def generate_objects(fields) do
    {_mask_count, _mask, data} = encode_fields(fields)
    IO.iodata_to_binary(data)
  end

  def encode_fields(fields) do
    case encode_sorted(fields, 0, 0, 0, []) do
      :unsorted -> fields |> Enum.sort(&by_offset/2) |> encode_fields()
      {mask, highest_bit, data} -> {mask_count(highest_bit), mask, data}
    end
  end

  defp encode_sorted([], mask, highest_bit, _previous, data), do: {mask, highest_bit, data}

  defp encode_sorted([{_field, _value, {offset, _size, _type}} | _rest], _mask, _highest_bit, previous, _data)
       when offset < previous, do: :unsorted

  defp encode_sorted([{_field, _value, {offset, size, _type}} = entry | rest], mask, highest_bit, _previous, data) do
    mask = mask ||| ((1 <<< size) - 1) <<< offset
    encode_sorted(rest, mask, max(highest_bit, offset + size - 1), offset, [data | field(entry)])
  end

  defp mask_count(highest_bit), do: max(div(highest_bit + 32, 32), 1)

  defp mask_binary(mask_count, mask), do: <<mask::little-size(32 * mask_count)>>

  def flatten_field_structs(obj_or_structs, target \\ :self)

  def flatten_field_structs(%__MODULE__{} = obj, target) do
    [
      obj.object,
      obj.item,
      obj.container,
      obj.unit,
      obj.player,
      obj.game_object,
      obj.dynamic_object,
      obj.corpse
    ]
    |> Enum.reject(&is_nil/1)
    |> flatten_field_structs(target)
  end

  def flatten_field_structs(field_structs, target) when is_list(field_structs) do
    field_structs
    |> Enum.flat_map(fn field_struct ->
      field_struct.__struct__.to_list(field_struct, target)
    end)
  end

  defp by_offset({_, _, {offset1, _, _}}, {_, _, {offset2, _, _}}) do
    offset1 <= offset2
  end

  def field({_, value, {_, 2, :guid}}), do: <<value::little-size(64)>>
  def field({_, value, {_, size, :int}}), do: <<value::little-size(32 * size)>>
  def field({_, value, {_, size, :float}}), do: <<value::little-float-size(32 * size)>>
  def field({_, value, {_, size, :byte}}), do: <<value::binary-size(4 * size)>>
  def field({_, value, {_, size, :two_short}}), do: <<value::little-size(32 * size)>>
  def field({_, value, {_, _size, :bytes}}), do: value

  defp packet_body(%__MODULE__{update_type: :out_of_range_objects, out_of_range_guids: guids}, _recipient_guid)
       when is_list(guids) do
    [<<@update_type_out_of_range_objects, length(guids)::little-size(32)>> | Enum.map(guids, &BinaryUtils.pack_guid/1)]
  end

  defp packet_body(%__MODULE__{update_type: :values, object: object} = obj, recipient_guid) do
    {mask_count, mask, data} = obj |> recipient_fields(recipient_guid) |> encode_fields()

    [<<@update_type_values>>, BinaryUtils.pack_guid(object.guid), mask_count, mask_binary(mask_count, mask) | data]
  end

  defp packet_body(
         %__MODULE__{update_type: update_type, object: object, object_type: object_type} = obj,
         recipient_guid
       )
       when update_type in [:create_object, :create_object2] do
    obj = %{obj | object: %{object | type: object_type_flags(obj)}}
    {mask_count, mask, data} = obj |> recipient_fields(recipient_guid) |> encode_fields()

    movement_block =
      obj.movement_block
      |> MovementBlock.refresh_timestamp(Time.now())
      |> MovementBlock.to_binary()

    [
      update_type(update_type),
      BinaryUtils.pack_guid(object.guid),
      object_type(object_type),
      movement_block,
      mask_count,
      mask_binary(mask_count, mask) | data
    ]
  end

  defp recipient_fields(%__MODULE__{} = obj, nil), do: flatten_field_structs(obj, :self)

  defp recipient_fields(%__MODULE__{object: %{guid: guid}} = obj, guid) do
    flatten_field_structs(obj, :self)
  end

  defp recipient_fields(%__MODULE__{object_type: :unit, unit: %Unit{summoned_by: owner}} = obj, owner)
       when is_integer(owner) and owner > 0 do
    flatten_field_structs(obj, :self)
  end

  defp recipient_fields(%__MODULE__{unit: %Unit{} = unit} = obj, recipient_guid) do
    target = if Empathy.visible_to?(unit, recipient_guid), do: :special_info, else: :other
    flatten_field_structs(%{obj | unit: Empathy.project(unit, recipient_guid)}, target)
  end

  defp recipient_fields(%__MODULE__{} = obj, _recipient_guid), do: flatten_field_structs(obj, :other)

  defp packet_header(%__MODULE__{} = obj) do
    <<1::little-size(32), transport_header([obj])>>
  end

  defp packet_header(objects) when is_list(objects) do
    <<Enum.count(objects)::little-size(32), transport_header(objects)>>
  end

  def to_packet(obj_or_objects, recipient_guid \\ nil)

  def to_packet(objects, recipient_guid) when is_list(objects) do
    objects = normalize(objects)
    bodies = Enum.map(objects, &packet_body(&1, recipient_guid))

    %Packet{
      opcode: @smsg_update_object,
      payload: IO.iodata_to_binary([packet_header(objects) | bodies])
    }
  end

  def to_packet(%__MODULE__{} = obj, recipient_guid) do
    %Packet{
      opcode: @smsg_update_object,
      payload: IO.iodata_to_binary([packet_header(obj) | packet_body(obj, recipient_guid)])
    }
  end

  def normalize(objects) when is_list(objects) do
    {removals, updates} =
      objects
      |> discard_removed_updates()
      |> Enum.split_with(&match?(%__MODULE__{update_type: :out_of_range_objects}, &1))

    case removals do
      [] ->
        updates

      [_ | _] ->
        guids = removals |> Enum.flat_map(& &1.out_of_range_guids) |> Enum.uniq()
        [out_of_range(guids, has_transport: Enum.any?(removals, &transport_update?/1)) | updates]
    end
  end

  defp discard_removed_updates(objects) do
    {updates, _removed} =
      objects
      |> Enum.reverse()
      |> Enum.reduce({[], MapSet.new()}, &retain_update/2)

    updates
  end

  defp retain_update(
         %__MODULE__{update_type: :out_of_range_objects, out_of_range_guids: guids} = update,
         {kept, removed}
       ) do
    {[update | kept], MapSet.union(removed, MapSet.new(guids))}
  end

  defp retain_update(%__MODULE__{object: %{guid: guid}} = update, {kept, removed}) do
    if MapSet.member?(removed, guid), do: {kept, removed}, else: {[update | kept], removed}
  end

  def out_of_range(guids, opts \\ []) when is_list(guids) do
    %__MODULE__{
      update_type: :out_of_range_objects,
      out_of_range_guids: guids,
      has_transport: Keyword.get(opts, :has_transport, false)
    }
  end

  defp transport_header(objects) do
    if Enum.any?(objects, &(transport_update?(&1) and &1.has_transport != false)), do: 1, else: 0
  end

  defp transport_update?(%__MODULE__{object: %{guid: guid}}) do
    Guid.high_guid(guid) == Guid.high_guid(:mo_transport)
  end

  defp transport_update?(%__MODULE__{update_type: :out_of_range_objects, has_transport: true}), do: true

  defp transport_update?(%__MODULE__{}), do: false

  def object_type_flags(%__MODULE__{} = obj) do
    Enum.reduce(@object_type_flags_map, 0, fn {field, type}, acc ->
      if Map.get(obj, field) == nil do
        acc
      else
        Bitwise.bor(acc, type)
      end
    end)
  end

  def from_item(%ItemCore{object: object, item: item, container: container} = data_item) do
    %__MODULE__{
      update_type: :create_object2,
      object_type: if(ItemCore.container?(data_item), do: :container, else: :item),
      object: object,
      item: item,
      container: container,
      movement_block: %MovementBlock{
        update_flag: 0
      }
    }
  end

  def item_values_update(%ItemCore{object: object, item: item, container: container} = data_item) do
    %__MODULE__{
      update_type: :values,
      object_type: if(ItemCore.container?(data_item), do: :container, else: :item),
      object: object,
      item: item,
      container: container
    }
  end
end
