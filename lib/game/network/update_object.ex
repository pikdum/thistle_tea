defmodule ThistleTea.Game.Network.UpdateObject do
  use ThistleTea.Game.Network.Opcodes, [:SMSG_UPDATE_OBJECT]

  alias ThistleTea.DB.Mangos.ItemTemplate
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Entity.Data.Component.Item
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Packet

  defstruct [
    :update_type,
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

  @item_guid_offset 0x40000000

  # TODO: would be neat to have a module to define flags + enums
  # or one module per enum/flag set?

  @update_type_values 0
  @update_type_movement 1
  @update_type_create_object 2
  @update_type_create_object2 3
  @update_type_out_of_range_objects 4
  @update_type_near_objects 5

  defp update_type(:values), do: @update_type_values
  defp update_type(:movement), do: @update_type_movement
  defp update_type(:create_object), do: @update_type_create_object
  defp update_type(:create_object2), do: @update_type_create_object2
  defp update_type(:out_of_range_objects), do: @update_type_out_of_range_objects
  defp update_type(:near_objects), do: @update_type_near_objects

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

  def mask_blocks_count(fields) do
    fields
    |> max_offset()
    |> Kernel./(32)
    |> ceil()
    |> trunc()
    |> max(1)
  end

  def max_offset(fields) do
    fields
    |> Enum.map(fn {_key, _value, {offset, _size, _type}} -> offset end)
    |> Enum.max()
  end

  # TODO: this still feels ugly
  def generate_mask(fields) do
    mask_count = mask_blocks_count(fields)
    mask_size = 32 * mask_count
    mask = Bitmap.new(mask_size)

    mask =
      Enum.reduce(fields, mask, fn {_field, _value, {offset, size, _type}}, acc ->
        start = offset
        stop = start + size - 1

        Enum.reduce(start..stop, acc, fn i, acc ->
          Bitmap.set(acc, i)
        end)
      end)

    <<mask.data::little-size(mask_size)>>
  end

  def generate_objects(fields) do
    fields
    |> Enum.sort(&by_offset/2)
    |> Enum.map(&field/1)
    |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)
  end

  def flatten_field_structs(%__MODULE__{} = obj) do
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
    |> flatten_field_structs()
  end

  def flatten_field_structs(field_structs) do
    field_structs
    |> Enum.flat_map(fn field_struct ->
      field_struct.__struct__.to_list(field_struct)
    end)
  end

  defp by_offset({_, _, {offset1, _, _}}, {_, _, {offset2, _, _}}) do
    offset1 <= offset2
  end

  def field({_, value, {_, 2, :guid}}), do: <<value::little-size(64)>>
  def field({_, value, {_, size, :int}}), do: <<value::little-size(32 * size)>>
  def field({_, value, {_, size, :float}}), do: <<value::little-float-size(32 * size)>>
  def field({_, value, {_, size, :byte}}), do: <<value::binary-size(4 * size)>>
  def field({_, value, {_, size, :two_short}}), do: <<value::little-size(16 * size)>>
  def field({_, value, {_, _size, :bytes}}), do: value

  def build_bytes([]), do: <<>>

  def build_bytes([{size, value} | rest]) do
    value = value || 0
    <<value::little-size(size)>> <> build_bytes(rest)
  end

  defp packet_body(%__MODULE__{update_type: :values, object: object} = obj) do
    fields = flatten_field_structs(obj)
    packed_guid = BinaryUtils.pack_guid(object.guid)
    mask_count = mask_blocks_count(fields)
    mask = generate_mask(fields)
    objects = generate_objects(fields)

    <<@update_type_values>> <> packed_guid <> <<mask_count>> <> mask <> objects
  end

  defp packet_body(%__MODULE__{update_type: update_type, object: object, object_type: object_type} = obj)
       when update_type in [:create_object, :create_object2] do
    obj = %{obj | object: Map.put(object, :type, object_type_flags(obj))}
    fields = flatten_field_structs(obj)
    packed_guid = BinaryUtils.pack_guid(object.guid)
    mask_count = mask_blocks_count(fields)
    mask = generate_mask(fields)
    objects = generate_objects(fields)
    movement_block = MovementBlock.to_binary(obj.movement_block)

    <<update_type(update_type)>> <>
      packed_guid <>
      <<object_type(object_type)>> <>
      movement_block <>
      <<mask_count>> <>
      mask <>
      objects
  end

  defp packet_header(%__MODULE__{} = _obj) do
    <<1::little-size(32), 0>>
  end

  defp packet_header(objects) when is_list(objects) do
    <<Enum.count(objects)::little-size(32), 0>>
  end

  def to_packet(objects) when is_list(objects) do
    header = packet_header(objects)

    payload =
      Enum.reduce(objects, header, fn obj, acc ->
        acc <> packet_body(obj)
      end)

    %Packet{
      opcode: @smsg_update_object,
      payload: payload
    }
  end

  def to_packet(%__MODULE__{} = obj) do
    %Packet{
      opcode: @smsg_update_object,
      payload: packet_header(obj) <> packet_body(obj)
    }
  end

  def object_type_flags(%__MODULE__{} = obj) do
    Enum.reduce(@object_type_flags_map, 0, fn {field, type}, acc ->
      if Map.get(obj, field) == nil do
        acc
      else
        Bitwise.bor(acc, type)
      end
    end)
  end

  # TODO: items need a proper lifecycle, this is just a hack
  def get_item_packets(%Player{} = player) do
    [
      player.visible_item_1_0,
      player.visible_item_2_0,
      player.visible_item_3_0,
      player.visible_item_4_0,
      player.visible_item_5_0,
      player.visible_item_6_0,
      player.visible_item_7_0,
      player.visible_item_8_0,
      player.visible_item_9_0,
      player.visible_item_10_0,
      player.visible_item_11_0,
      player.visible_item_12_0,
      player.visible_item_13_0,
      player.visible_item_14_0,
      player.visible_item_15_0,
      player.visible_item_16_0,
      player.visible_item_17_0,
      player.visible_item_18_0,
      player.visible_item_19_0
    ]
    |> Enum.filter(fn item_entry -> is_integer(item_entry) and item_entry > 0 end)
    |> Enum.map(fn item_entry ->
      item = Repo.get(ItemTemplate, item_entry)

      %__MODULE__{
        update_type: :create_object2,
        object_type: :item,
        object: %Object{
          guid: item.entry + @item_guid_offset,
          entry: item.entry
        },
        item: %Item{
          flags: item.flags
        },
        movement_block: %MovementBlock{
          update_flag: 0
        }
      }
    end)
    |> Enum.chunk_every(20)
    |> Enum.map(&to_packet/1)
  end
end
