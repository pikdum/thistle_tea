defmodule ThistleTea.Game.Entity.Logic.Aura.TriggeredLifetime do
  @moduledoc "Keeps permanent triggered auras within the lifetime of their source aura on the same bearer."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  def reconcile(previous, desired) do
    retained = MapSet.new(desired, &Holder.key/1)
    removed = Enum.reject(previous, &MapSet.member?(retained, Holder.key(&1)))

    remaining =
      Enum.reject(desired, fn child ->
        Enum.any?(removed, &dependent?(&1.spell, child.spell))
      end)

    if remaining == desired, do: desired, else: reconcile(previous, remaining)
  end

  def source(%{unit: %{auras: holders}}, %Spell{} = parent, %Spell{} = child) when is_list(holders) do
    if dependent?(parent, child) do
      case Enum.find(holders, &(&1.spell.id == parent.id)) do
        %Holder{} = holder -> {Holder.key(holder), holder.applied_at}
        nil -> :missing
      end
    end
  end

  def source(_entity, _parent, _child), do: nil

  def source_alive?(_entity, nil, _now), do: true
  def source_alive?(_entity, :missing, _now), do: false

  def source_alive?(%{unit: %{auras: holders}}, {key, applied_at}, now) when is_list(holders) do
    Enum.any?(holders, &(Holder.key(&1) == key and &1.applied_at == applied_at and Holder.alive?(&1, now)))
  end

  defp dependent?(%Spell{effects: effects, duration_ms: duration}, %Spell{id: id, duration_ms: -1}) do
    Enum.any?(effects, fn
      %Effect{aura: :periodic_trigger_spell, amplitude_ms: ^duration} -> false
      %Effect{aura: aura, trigger_spell_id: ^id} when aura not in [nil, :none] -> true
      _effect -> false
    end)
  end

  defp dependent?(_parent, _child), do: false
end
