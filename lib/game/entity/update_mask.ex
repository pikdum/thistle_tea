defmodule ThistleTea.Game.Entity.UpdateMask do
  @moduledoc """
  `use` macro that turns a keyword list of update fields (offset, size,
  encoder, visibility) into a component struct plus `to_list/2` for building
  SMSG_UPDATE_OBJECT values blocks.
  """
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
      @metadata Map.new(unquote(fields))
      defstruct unquote(build_struct(fields))

      defp virtual_field?({_, :virtual}), do: true
      defp virtual_field?({_, {:virtual, _default}}), do: true
      defp virtual_field?(_), do: false

      defp private_field?({_, {_, _, _, :private}}), do: true
      defp private_field?(_), do: false

      defp strip_visibility({field, {offset, size, type, _vis}}), do: {field, {offset, size, type}}
      defp strip_visibility(entry), do: entry

      def to_list(struct, target \\ :self) do
        @metadata
        |> Enum.reject(&virtual_field?/1)
        |> filter_visibility(target)
        |> Enum.map(&strip_visibility/1)
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

      defp filter_visibility(entries, :self), do: entries
      defp filter_visibility(entries, :other), do: Enum.reject(entries, &private_field?/1)
    end
  end
end
