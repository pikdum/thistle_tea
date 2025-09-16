defmodule ThistleTea.Game.FieldStruct do
  defmacro __using__(fields) do
    quote do
      @metadata Map.new(unquote(fields))
      defstruct unquote(Keyword.keys(fields))

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
