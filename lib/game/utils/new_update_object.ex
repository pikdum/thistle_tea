defmodule ThistleTea.Game.Utils.NewUpdateObject do
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
      Enum.reduce(fields, mask, fn {field, value, {offset, size, _type}}, acc ->
        start = offset
        stop = start + size - 1

        Enum.reduce(start..stop, acc, fn i, acc ->
          Bitmap.set(acc, i)
        end)
      end)

    <<mask.data::little-size(mask_size)>>
  end

  def flatten_field_structs(field_structs) do
    field_structs
    |> Enum.flat_map(fn field_struct ->
      field_struct.__struct__.to_list(field_struct)
    end)
  end

  def field(_, value, {_, 2, :guid}), do: <<value::little-size(64)>>
  def field(_, value, {_, size, :int}), do: <<value::little-size(32 * size)>>
  def field(_, value, {_, size, :float}), do: <<value::little-float-size(32 * size)>>
  def field(_, value, {_, size, :byte}), do: <<value::binary-size(4 * size)>>
  def field(_, value, {_, size, :two_short}), do: <<value::little-size(16 * size)>>

  # TODO: figure out how to handle arrays of structs
  # do i just use functions for the custom ones too?
end
