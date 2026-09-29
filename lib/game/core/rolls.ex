defmodule ThistleTea.Game.Core.Rolls do
  @moduledoc """
  Named random rolls for rules that must stay reproducible.

  `system/0` draws every roll from the calling process's `:rand` state.
  `fixed/1` pins the rolls a caller names and draws the rest, so a test can
  force one outcome, such as a melee hit, without seeding the whole process.
  `pinned/2` hands the pinned rolls to APIs that take them as keyword options
  and draw lazily, like `AttackTable.roll_special/3`.
  The source is plain data rather than closures, so it can ride on structs
  such as `CastContext` that cross processes and outlive a code reload.
  """
  alias ThistleTea.Game.Core.Math

  defstruct fixed: %{}

  def system, do: %__MODULE__{}

  def fixed(rolls) when is_list(rolls) or is_map(rolls), do: %__MODULE__{fixed: Map.new(rolls)}

  def integer(%__MODULE__{fixed: fixed}, name, lower, upper)
      when is_atom(name) and is_integer(lower) and is_integer(upper) and lower <= upper do
    case fixed do
      %{^name => value} when is_integer(value) -> value |> max(lower) |> min(upper)
      _ -> Math.random_int(lower, upper)
    end
  end

  def pinned(%__MODULE__{fixed: fixed}, names) when is_list(names) do
    for {name, key} <- names, Map.has_key?(fixed, name), do: {key, Map.fetch!(fixed, name)}
  end

  def uniform(%__MODULE__{fixed: fixed}, name) when is_atom(name) do
    case fixed do
      %{^name => value} when is_float(value) and value >= 0.0 and value <= 1.0 -> value
      _ -> :rand.uniform()
    end
  end
end
