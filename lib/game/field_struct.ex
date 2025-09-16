defmodule ThistleTea.Game.FieldStruct do
  defp build_struct(fields) do
    fields
    |> Keyword.reject(&fn_field?/1)
    |> Keyword.keys()
  end

  defp fn_field?({_, {_offset, _size, {:fn, _args, _fn}}}), do: true
  defp fn_field?(_), do: false

  defmacro __using__(fields) do
    quote do
      @metadata Map.new(unquote(fields))
      defstruct unquote(build_struct(fields))

      defp virtual_field?({_, :virtual}), do: true
      defp virtual_field?(_), do: false

      def to_list(struct) do
        @metadata
        |> Enum.reject(&virtual_field?/1)
        |> Enum.map(fn
          {field, {offset, size, {:fn, params, func}}} ->
            args = Map.take(struct, params)
            value = func.(args)
            {field, value, {offset, size, :bytes}}

          {field, metadata} ->
            {field, Map.get(struct, field), metadata}
        end)
        |> Enum.reject(fn {_field, value, _metadata} -> is_nil(value) end)
      end
    end
  end
end
