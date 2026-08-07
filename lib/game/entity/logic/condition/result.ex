defmodule ThistleTea.Game.Entity.Logic.Condition.Result do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Reason

  def compare(actual, expected, 0) when is_number(actual) and is_number(expected), do: actual == expected
  def compare(actual, expected, 1) when is_number(actual) and is_number(expected), do: actual >= expected
  def compare(actual, expected, 2) when is_number(actual) and is_number(expected), do: actual <= expected
  def compare(_actual, _expected, _mode), do: {:error, :invalid_comparison}

  def compare_result(actual, expected, comparison, condition) do
    case compare(actual, expected, comparison) do
      result when is_boolean(result) -> truth(result)
      {:error, reason} -> unknown(condition, reason)
    end
  end

  def percentage(_current, maximum, _expected, _comparison, condition, resource) when maximum <= 0 do
    unknown(condition, {:invalid_maximum, resource})
  end

  def percentage(current, maximum, expected, comparison, condition, _resource) do
    compare_result(trunc(current * 100 / maximum), expected, comparison, condition)
  end

  def combine_and(results) do
    cond do
      :unmet in results -> :unmet
      reasons = unknown_reasons(results) -> {:unknown, reasons}
      true -> :met
    end
  end

  def combine_or(results) do
    cond do
      :met in results -> :met
      reasons = unknown_reasons(results) -> {:unknown, reasons}
      true -> :unmet
    end
  end

  def negate(:met), do: :unmet
  def negate(:unmet), do: :met
  def negate({:unknown, reasons}), do: {:unknown, reasons}

  def truth(true), do: :met
  def truth(false), do: :unmet

  def unknown(%Condition{} = condition, capability) do
    {:unknown, [%Reason{entry: condition.entry, type: condition.type, capability: capability}]}
  end

  defp unknown_reasons(results) do
    reasons =
      results
      |> Enum.flat_map(fn
        {:unknown, reasons} -> reasons
        _result -> []
      end)
      |> Enum.uniq()

    if reasons != [], do: reasons
  end
end
