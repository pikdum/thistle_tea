defmodule ThistleTea.Game.Entity.Logic.Aura.Linked do
  @moduledoc "Reconciles linked holders and form-dependent boosts with the parent applications that own them."

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.Application
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Shapeshift
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Scripts

  def reconcile(entity, previous, desired, now) do
    form = if Death.alive?(entity), do: Shapeshift.form(desired), else: 0
    previous_form = Shapeshift.form(previous)

    requested =
      MapSet.new(
        for parent <- previous,
            {spell, kind} <- linked_spells(parent, previous_form),
            kind == :passive or previous_form == form,
            do: link_key(parent, spell)
      )

    retained =
      Map.new(for %Holder{linked_from: source, spell: spell} = holder <- desired, do: {{source, spell.id}, holder})

    desired
    |> Enum.filter(&is_nil(&1.linked_from))
    |> Enum.flat_map(&expand(&1, entity, requested, retained, form, now))
    |> retain_owned_area_sources()
  end

  defp retain_owned_area_sources(holders) do
    owned =
      MapSet.new(
        for holder <- holders, not is_nil(holder.linked_from) and is_number(holder.area_radius), do: holder.spell.id
      )

    Enum.reject(holders, &(is_nil(&1.linked_from) and MapSet.member?(owned, &1.spell.id)))
  end

  def active?(%Holder{linked_from: nil}, _holders, _now), do: true

  def active?(%Holder{linked_from: {key, applied_at}}, holders, now) do
    case Enum.find(holders, &(Holder.key(&1) == key and &1.applied_at == applied_at)) do
      %Holder{} = parent -> Holder.alive?(parent, now) and active?(parent, holders, now)
      nil -> false
    end
  end

  defp expand(%Holder{} = parent, entity, requested, retained, form, now) do
    children =
      parent
      |> linked_spells(form)
      |> Enum.flat_map(fn {spell, kind} ->
        key = link_key(parent, spell)

        child = retained_child(retained, requested, key, entity, {spell, kind}, now)

        if child, do: expand(child, entity, requested, retained, form, now), else: []
      end)

    [parent | children]
  end

  defp retained_child(retained, requested, key, entity, link, now) do
    case Map.fetch(retained, key) do
      {:ok, holder} -> holder
      :error -> if not MapSet.member?(requested, key), do: build_child(entity, link, elem(key, 0), now)
    end
  end

  defp build_child(entity, {spell, :passive}, source, now), do: Application.linked_holder(entity, spell, source, now)
  defp build_child(entity, {spell, :form}, source, now), do: Application.form_holder(entity, spell, source, now)

  defp linked_spells(%Holder{spell: %Spell{linked_auras: spells}, auras: auras} = parent, form) do
    ids = for %Aura{type: :linked_aura, trigger_spell_id: id} <- auras, do: id
    passive = for spell <- spells, spell.id in ids, do: {spell, :passive}

    conditional =
      for spell <- parent.spell.form_auras,
          form > 0 and Spell.shapeshift_cast_error(spell, form) == :ok,
          do: {Scripts.form_aura_spell(parent, spell), :form}

    passive ++ conditional
  end

  defp link_key(%Holder{} = parent, %Spell{id: id}), do: {{Holder.key(parent), parent.applied_at}, id}
end
