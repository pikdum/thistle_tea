defmodule ThistleTea.Game.Entity.Data.Condition do
  @moduledoc """
  One vmangos `conditions` row resolved into a tree at load time: combinators
  (`:and`/`:or`/`:not`) carry their referenced conditions as `children`, leaf
  types keep their raw values. Unsupported types keep their numeric id as
  `{:unsupported, id}` so the evaluator can log and treat them as met, and
  rows whose combinator children failed to resolve become
  `{:unsupported, :unresolved}`.
  """
  import Bitwise, only: [&&&: 2]

  defstruct entry: 0,
            type: {:unsupported, 0},
            value1: 0,
            value2: 0,
            value3: 0,
            value4: 0,
            reverse?: false,
            swap_targets?: false,
            children: []

  @flag_reverse_result 0x1
  @flag_swap_targets 0x2

  def build(row, children) when is_map(row) and is_list(children) do
    type = type(row.type)

    %__MODULE__{
      entry: row.condition_entry,
      type: resolve_type(type, children),
      value1: int(row.value1),
      value2: int(row.value2),
      value3: int(row.value3),
      value4: int(row.value4),
      reverse?: flag?(row.flags, @flag_reverse_result),
      swap_targets?: flag?(row.flags, @flag_swap_targets),
      children: children
    }
  end

  def combinator_child_entries(row) when is_map(row) do
    case type(row.type) do
      :not -> Enum.filter([row.value1], &positive?/1)
      type when type in [:or, :and] -> Enum.filter([row.value1, row.value2, row.value3, row.value4], &positive?/1)
      _ -> []
    end
  end

  defp resolve_type(type, children) when type in [:not, :or, :and] do
    if children == [] or Enum.any?(children, &is_nil/1) do
      {:unsupported, :unresolved}
    else
      type
    end
  end

  defp resolve_type(type, _children), do: type

  defp positive?(value), do: is_integer(value) and value > 0

  defp int(value) when is_integer(value), do: value
  defp int(_value), do: 0

  defp flag?(flags, bit) when is_integer(flags), do: (flags &&& bit) != 0
  defp flag?(_flags, _bit), do: false

  defp type(-3), do: :not
  defp type(-2), do: :or
  defp type(-1), do: :and
  defp type(0), do: :none
  defp type(16), do: :source_entry
  defp type(52), do: :db_guid
  defp type(other), do: {:unsupported, other}
end
