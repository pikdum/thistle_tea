defmodule ThistleTea.Game.Entity.Logic.AttackFeedback do
  @moduledoc """
  Applies the resolved outcome of an entity's own outgoing swing or melee
  ability, delivered back from the defender that rolled the attack table: rage
  from damage dealt, partial rage from dodged/parried swings, the vanilla 82%
  power refund when a rage ability is dodged or parried, and the hidden combo
  point that marks a dodging target for Overpower. Swings that carried a
  queued on-next-swing spell generate no rage.
  """
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts

  @avoided_rage_factor 0.75
  @avoided_power_refund 0.82

  def receive(entity, payload, spell \\ nil, now) do
    entity
    |> apply_power_feedback(payload, spell)
    |> apply_rogue_combo_feedback(payload, spell)
    |> stop_incapacitate_auto_attack(payload, spell)
    |> trigger_blade_flurry(payload)
    |> Paladin.trigger_seal(payload)
    |> mark_reactives(payload, now)
  end

  defp apply_power_feedback(entity, %{outcome: outcome}, %Spell{} = spell) when outcome in [:dodge, :parry] do
    cond do
      Scripts.finisher?(spell) -> Resources.refund_power(entity, spell, 0.8)
      Spell.attribute?(spell, :discount_power_on_miss) -> Resources.refund_power(entity, spell, @avoided_power_refund)
      true -> entity
    end
  end

  defp apply_power_feedback(entity, %{spell_id: spell_id}, _spell) when is_integer(spell_id) do
    entity
  end

  defp apply_power_feedback(entity, %{outcome: outcome, damage: damage}, _spell)
       when outcome in [:dodge, :parry] and is_number(damage) do
    Resources.gain_attack_rage(entity, damage * @avoided_rage_factor, :dealt)
  end

  defp apply_power_feedback(entity, %{outcome: :miss}, %Spell{} = spell) do
    if Scripts.finisher?(spell), do: Resources.refund_power(entity, spell, 0.8), else: entity
  end

  defp apply_power_feedback(entity, %{outcome: :miss}, _spell), do: entity

  defp apply_power_feedback(entity, %{damage: damage}, _spell) when is_number(damage) and damage > 0 do
    Resources.gain_attack_rage(entity, damage, :dealt)
  end

  defp apply_power_feedback(entity, _payload, _spell), do: entity

  defp apply_rogue_combo_feedback(entity, %{outcome: outcome, victim_guid: victim_guid}, %Spell{} = spell)
       when outcome in [:normal, :crit] do
    amount =
      Enum.reduce(spell.effects, 0, fn
        %Effect{type: :add_combo_points} = effect, acc -> acc + max(Effect.damage_roll(effect), 0)
        _effect, acc -> acc
      end)

    cond do
      Scripts.finisher?(spell) -> Reactive.consume_combo(entity)
      amount > 0 -> Reactive.add_combo_points(entity, victim_guid, amount)
      true -> entity
    end
  end

  defp apply_rogue_combo_feedback(entity, _payload, _spell), do: entity

  defp stop_incapacitate_auto_attack(entity, %{outcome: outcome, victim_guid: victim_guid}, %Spell{name: name})
       when name in ["Gouge", "Scatter Shot"] and outcome in [:normal, :crit] do
    entity
    |> BT.clear_auto_attack()
    |> Event.enqueue(Event.attack_stop(entity.object.guid, victim_guid))
  end

  defp stop_incapacitate_auto_attack(entity, _payload, _spell), do: entity

  defp trigger_blade_flurry(entity, %{victim_guid: victim_guid, damage: damage})
       when is_integer(damage) and damage > 0 do
    if Aura.has_spell?(entity, 13_877) do
      Event.enqueue(entity, Event.blade_flurry(victim_guid, damage))
    else
      entity
    end
  end

  defp trigger_blade_flurry(entity, _payload), do: entity

  defp mark_reactives(entity, %{outcome: :dodge, victim_guid: victim_guid}, now) do
    Reactive.mark_dodging_target(entity, victim_guid, now)
  end

  defp mark_reactives(entity, _payload, _now), do: entity
end
