defmodule ThistleTea.Game.Entity.Logic.Aura.Capacity do
  @moduledoc "Enforces separate visible buff and debuff capacities before aura transitions project gameplay state."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.Priority
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync

  def retain(holders, target_guid) do
    indexed = Enum.with_index(holders)

    removed =
      for {negative?, limit} <- [{false, 32}, {true, 16}],
          index <- overflow(indexed, target_guid, negative?, limit),
          into: MapSet.new(),
          do: index

    for {holder, index} <- indexed, not MapSet.member?(removed, index), do: holder
  end

  defp overflow(indexed, target_guid, negative?, limit) do
    visible =
      Enum.filter(indexed, fn {holder, _index} ->
        holder.negative? == negative? and UnitSync.visible?(holder, target_guid)
      end)

    if length(visible) > limit do
      visible
      |> Enum.sort_by(fn {%Holder{} = holder, index} ->
        {Priority.value(holder, target_guid), holder.applied_at || 0, holder.spell.id, index}
      end)
      |> Enum.take(length(visible) - limit)
      |> Enum.map(&elem(&1, 1))
    else
      []
    end
  end
end
