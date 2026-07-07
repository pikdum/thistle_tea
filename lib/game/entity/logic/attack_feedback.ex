defmodule ThistleTea.Game.Entity.Logic.AttackFeedback do
  @moduledoc """
  Applies the resolved outcome of an entity's own outgoing swing or melee
  ability, delivered back from the defender that rolled the attack table: rage
  from damage dealt, partial rage from dodged/parried swings, the vanilla 82%
  power refund when a rage ability is dodged or parried, and the hidden combo
  point that marks a dodging target for Overpower. Swings that carried a
  queued on-next-swing spell generate no rage.
  """
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell

  @avoided_rage_factor 0.75
  @avoided_power_refund 0.82

  def receive(entity, payload, spell \\ nil, now) do
    entity
    |> apply_power_feedback(payload, spell)
    |> mark_reactives(payload, now)
  end

  defp apply_power_feedback(entity, %{outcome: outcome}, %Spell{} = spell) when outcome in [:dodge, :parry] do
    if Spell.attribute?(spell, :discount_power_on_miss) do
      Resources.refund_power(entity, spell, @avoided_power_refund)
    else
      entity
    end
  end

  defp apply_power_feedback(entity, %{spell_id: spell_id}, _spell) when is_integer(spell_id) do
    entity
  end

  defp apply_power_feedback(entity, %{outcome: outcome, damage: damage}, _spell)
       when outcome in [:dodge, :parry] and is_number(damage) do
    Resources.gain_attack_rage(entity, damage * @avoided_rage_factor, :dealt)
  end

  defp apply_power_feedback(entity, %{outcome: :miss}, _spell), do: entity

  defp apply_power_feedback(entity, %{damage: damage}, _spell) when is_number(damage) and damage > 0 do
    Resources.gain_attack_rage(entity, damage, :dealt)
  end

  defp apply_power_feedback(entity, _payload, _spell), do: entity

  defp mark_reactives(entity, %{outcome: :dodge, victim_guid: victim_guid}, now) do
    Reactive.mark_dodging_target(entity, victim_guid, now)
  end

  defp mark_reactives(entity, _payload, _now), do: entity
end
