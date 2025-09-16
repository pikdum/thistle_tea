defmodule ThistleTea.Game.FieldStruct do
  defmacro __using__(fields) do
    quote do
      defstruct unquote(Keyword.keys(fields))

      def offset(field), do: get_elem(field, 0)
      def size(field), do: get_elem(field, 1)
      def type(field), do: get_elem(field, 2)

      # helper that can simplify the above 3 functions
      defp get_elem(field, index) do
        case unquote(fields)[field] do
          nil -> nil
          tuple -> elem(tuple, index)
        end
      end
    end
  end
end
