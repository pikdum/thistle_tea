defmodule ThistleTea.Game.Core.Entity.UpdateMask do
  @moduledoc """
  `use` macro that turns a keyword list of update fields (offset, size,
  encoder, visibility) into a component struct plus `to_list/2` for building
  SMSG_UPDATE_OBJECT values blocks.

  The field specs for each visibility target (`:self`, `:other`,
  `:special_info`) are resolved at compile time and sorted by offset, so
  `to_list/2` walks only the fields a recipient can see, in wire order.
  """
  @targets [:self, :other, :special_info]

  def build_bytes([]), do: <<>>

  def build_bytes([{size, value} | rest]) do
    value = value || 0
    <<value::little-size(size)>> <> build_bytes(rest)
  end

  def field_specs(fields, target) when target in @targets do
    fields
    |> Enum.reject(&virtual_field?/1)
    |> Enum.filter(&visible_field?(&1, target))
    |> Enum.map(&field_spec/1)
    |> Enum.sort_by(fn {_field, offset, _size, _type} -> offset end)
  end

  def values(struct, specs), do: values(struct, specs, [])

  defp values(_struct, [], acc), do: :lists.reverse(acc)

  defp values(struct, [{field, offset, size, {:fn, params, func}} | rest], acc) do
    case func.(Map.take(struct, params)) do
      nil -> values(struct, rest, acc)
      value -> values(struct, rest, [{field, value, {offset, size, :bytes}} | acc])
    end
  end

  defp values(struct, [{field, offset, size, type} | rest], acc) do
    case Map.get(struct, field) do
      nil -> values(struct, rest, acc)
      value -> values(struct, rest, [{field, value, {offset, size, type}} | acc])
    end
  end

  defp virtual_field?({_field, :virtual}), do: true
  defp virtual_field?({_field, {:virtual, _default}}), do: true
  defp virtual_field?(_entry), do: false

  defp visible_field?(_entry, :self), do: true
  defp visible_field?({_field, {_offset, _size, _type, visibility}}, target), do: visibility == target
  defp visible_field?(_entry, _target), do: true

  defp field_spec({field, {offset, size, type, _visibility}}), do: {field, offset, size, type}
  defp field_spec({field, {offset, size, type}}), do: {field, offset, size, type}

  defp build_struct(fields) do
    fields
    |> Keyword.reject(&fn_field?/1)
    |> Enum.map(fn
      {key, {:virtual, default}} -> {key, default}
      {key, _metadata} -> key
    end)
  end

  defp fn_field?({_, {_offset, _size, {:fn, _args, _fn}}}), do: true
  defp fn_field?({_, {_offset, _size, {:fn, _args, _fn}, _vis}}), do: true
  defp fn_field?(_), do: false

  defmacro __using__(fields) do
    quote do
      defstruct unquote(build_struct(fields))

      @self_fields unquote(__MODULE__).field_specs(unquote(fields), :self)
      @other_fields unquote(__MODULE__).field_specs(unquote(fields), :other)
      @special_info_fields unquote(__MODULE__).field_specs(unquote(fields), :special_info)

      def to_list(struct, target \\ :self)
      def to_list(struct, :self), do: unquote(__MODULE__).values(struct, @self_fields)
      def to_list(struct, :other), do: unquote(__MODULE__).values(struct, @other_fields)

      def to_list(struct, :special_info), do: unquote(__MODULE__).values(struct, @special_info_fields)
    end
  end
end
