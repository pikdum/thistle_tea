defmodule ThistleTea.Game.Entity.Logic.Aura.Linked do
  @moduledoc "Reconciles passive linked holders with the parent applications that own them."

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.Application
  alias ThistleTea.Game.Spell

  def reconcile(entity, previous, desired, now) do
    requested = MapSet.new(for parent <- previous, spell <- linked_spells(parent), do: link_key(parent, spell))

    retained =
      Map.new(for %Holder{linked_from: source, spell: spell} = holder <- desired, do: {{source, spell.id}, holder})

    desired
    |> Enum.filter(&is_nil(&1.linked_from))
    |> Enum.flat_map(&expand(&1, entity, requested, retained, now))
  end

  def active?(%Holder{linked_from: nil}, _holders, _now), do: true

  def active?(%Holder{linked_from: {key, applied_at}}, holders, now) do
    case Enum.find(holders, &(Holder.key(&1) == key and &1.applied_at == applied_at)) do
      %Holder{} = parent -> Holder.alive?(parent, now) and active?(parent, holders, now)
      nil -> false
    end
  end

  defp expand(%Holder{} = parent, entity, requested, retained, now) do
    children =
      parent
      |> linked_spells()
      |> Enum.flat_map(fn spell ->
        key = link_key(parent, spell)

        child = retained_child(retained, requested, key, entity, spell, now)

        if child, do: expand(child, entity, requested, retained, now), else: []
      end)

    [parent | children]
  end

  defp retained_child(retained, requested, key, entity, spell, now) do
    case Map.fetch(retained, key) do
      {:ok, holder} -> holder
      :error -> if not MapSet.member?(requested, key), do: Application.linked_holder(entity, spell, elem(key, 0), now)
    end
  end

  defp linked_spells(%Holder{spell: %Spell{linked_auras: spells}, auras: auras}) do
    ids = for %Aura{type: :linked_aura, trigger_spell_id: id} <- auras, do: id
    Enum.filter(spells, &(&1.id in ids))
  end

  defp link_key(%Holder{} = parent, %Spell{id: id}), do: {{Holder.key(parent), parent.applied_at}, id}
end
