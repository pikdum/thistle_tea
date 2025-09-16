defmodule ThistleTea.Game.FieldStruct do
  def build(fields) do
    byte_fields = byte_fields(fields)
    without = Keyword.drop(fields, Keyword.keys(byte_fields))
    inverted = invert_byte_fields(byte_fields)
    Keyword.merge(without, inverted)
  end

  defp byte_fields(fields) do
    Keyword.filter(fields, fn
      {_k, {_offset, _size, {:bytes, list}}} when is_list(list) -> true
      {_k, v} -> false
    end)
  end

  defp invert_byte_fields(byte_fields) do
    Enum.flat_map(byte_fields, fn {_k, {offset, size, {:bytes, list}}} ->
      list
      |> Enum.with_index()
      |> Enum.map(fn {{field, type}, index} ->
        {field, {offset, size, {:bytes_part, index, type}}}
      end)
    end)
  end

  defmacro __using__(fields) do
    quote do
      @metadata Map.new(unquote(fields))
      defstruct unquote(Keyword.keys(build(fields)))

      def offset(field), do: get_elem(field, 0)
      def size(field), do: get_elem(field, 1)
      def type(field), do: get_elem(field, 2)
      def metadata(field), do: Map.get(@metadata, field)
      def metadata, do: @metadata

      defp get_elem(field, index) do
        @metadata
        |> Map.get(field)
        |> elem(index)
      end
    end
  end
end
