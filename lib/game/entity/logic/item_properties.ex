defmodule ThistleTea.Game.Entity.Logic.ItemProperties do
  @moduledoc "Pure weighted selection of item properties from a template's probability table."

  def select(entries, roll) when is_list(entries) and roll >= 0 and roll <= 1 do
    entries = Enum.filter(entries, fn {_id, weight} -> weight > 0.000001 and weight <= 100 end)
    total = Enum.reduce(entries, 0, fn {_id, weight}, total -> total + weight end)
    pick(entries, roll * total)
  end

  defp pick([], _roll), do: nil
  defp pick([{id, _weight}], _roll), do: id
  defp pick([{id, weight} | _rest], roll) when roll <= weight, do: id
  defp pick([{_id, weight} | rest], roll), do: pick(rest, roll - weight)
end
