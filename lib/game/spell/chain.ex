defmodule ThistleTea.Game.Spell.Chain do
  @moduledoc """
  Plans per-effect recipients and attenuation for ordered chain spell impacts.
  Hit rolls advance each effect independently; misses do not consume attenuation.
  """

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers

  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &chain_effect?/1)

  def count(caster, %Spell{effects: effects} = spell) do
    effects
    |> Enum.filter(&chain_effect?/1)
    |> Enum.map(&effect_count(caster, spell, &1))
    |> Enum.max(fn -> 1 end)
  end

  def healing?(%Spell{effects: effects}) do
    Enum.any?(effects, &(&1.implicit_target_a == :chain_heal))
  end

  def plan(caster, %Spell{} = spell, targets, hits) do
    if count(caster, spell) > 1 do
      modifiers = Modifiers.snapshot(caster, spell)

      Enum.reduce(spell.effects, %{}, fn effect, plan ->
        recipients = recipients(caster, spell, effect, targets)
        multiplier = max(Modifiers.value(modifiers, :effect_past_first, effect.damage_multiplier), 0)

        plan_effect(plan, effect, recipients, hits, multiplier)
      end)
    end
  end

  defp plan_effect(plan, effect, recipients, hits, multiplier) do
    {plan, _multiplier} =
      Enum.reduce(recipients, {plan, 1.0}, fn guid, {plan, current} ->
        plan = Map.update(plan, guid, %{effect.index => current}, &Map.put(&1, effect.index, current))
        next = if guid in hits and attenuated?(effect), do: current * multiplier, else: current
        {plan, next}
      end)

    plan
  end

  def put_context(%CastContext{} = context, nil), do: %{context | chain_effects: nil}

  def put_context(%CastContext{} = context, plan) do
    %{context | chain_effects: Map.get(plan, context.target_guid, %{})}
  end

  def effects(effects, %CastContext{chain_effects: nil}), do: effects

  def effects(effects, %CastContext{chain_effects: selected}) do
    Enum.filter(effects, &Map.has_key?(selected, &1.index))
  end

  def scale(amount, %Effect{index: index}, %CastContext{chain_effects: effects}) when is_map(effects) do
    trunc(amount * Map.get(effects, index, 1.0))
  end

  def scale(amount, _effect, _context), do: amount

  defp recipients(caster, spell, effect, targets) do
    cond do
      effect.implicit_target_a == :caster ->
        [caster.object.guid]

      chain_effect?(effect) ->
        targets
        |> Enum.reject(&(effect.implicit_target_a == :target_enemy and &1 == caster.object.guid))
        |> Enum.take(effect_count(caster, spell, effect))

      true ->
        Enum.take(targets, 1)
    end
  end

  defp effect_count(caster, spell, effect) do
    max(Modifiers.integer_value(caster, spell, :jump_targets, effect.chain_targets || 0), 1)
  end

  defp chain_effect?(%Effect{chain_targets: count}) when is_integer(count) and count > 0, do: true
  defp chain_effect?(_effect), do: false

  defp attenuated?(%Effect{implicit_target_a: target}), do: target in [:target_enemy, :chain_heal]
end
