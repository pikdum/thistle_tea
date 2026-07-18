defmodule ThistleTea.Game.Entity.Logic.AttackFeedback do
  @moduledoc """
  Applies the resolved outcome of an entity's own outgoing swing or melee
  ability, delivered back from the defender that rolled the attack table: rage
  from damage dealt, partial rage from dodged/parried swings, the vanilla 82%
  power refund when a rage ability is dodged or parried, and the hidden combo
  point that marks a dodging target for Overpower. Swings that carried a
  queued on-next-swing spell generate no rage.
  """
  alias ThistleTea.Game.Aura.Holder
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
    |> trigger_blade_flurry(payload, spell)
    |> Paladin.trigger_seal(payload)
    |> trigger_melee_procs(payload, spell, now)
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

  defp trigger_blade_flurry(entity, %{victim_guid: victim_guid, damage: damage} = payload, spell)
       when is_integer(damage) do
    proc_damage = Map.get(payload, :proc_damage, damage)
    proc_type = if match?(%Spell{}, spell), do: :deal_melee_ability, else: :deal_melee_swing
    damage_spell_id = blade_flurry_damage_spell(entity, proc_type)

    if is_integer(proc_damage) and proc_damage > 0 and is_integer(damage_spell_id) do
      Event.enqueue(entity, Event.blade_flurry(victim_guid, proc_damage, damage_spell_id))
    else
      entity
    end
  end

  defp trigger_blade_flurry(entity, _payload, _spell), do: entity

  defp blade_flurry_damage_spell(%{unit: %{auras: holders}}, proc_type) when is_list(holders) do
    Enum.find_value(holders, fn %Holder{spell: spell} ->
      if Scripts.rogue_blade_flurry?(spell) and Spell.procs_on?(spell, proc_type) do
        blade_flurry_trigger_id(spell)
      end
    end)
  end

  defp blade_flurry_damage_spell(_entity, _proc_type), do: nil

  defp blade_flurry_trigger_id(%Spell{effects: effects}) do
    Enum.find_value(effects, fn
      %Effect{type: :apply_aura, aura: :dummy, trigger_spell_id: id} when is_integer(id) and id > 0 -> id
      _effect -> nil
    end)
  end

  defp trigger_melee_procs(entity, %{outcome: outcome, victim_guid: victim_guid} = payload, spell, now)
       when outcome in [:normal, :crit] and is_integer(victim_guid) and is_integer(now) do
    proc_type = if match?(%Spell{}, spell), do: :deal_melee_ability, else: :deal_melee_swing

    {entity, events} =
      Aura.reactions(entity, :melee_hit_dealt, %{
        victim_guid: victim_guid,
        outcome: outcome,
        proc_type: proc_type,
        spell: spell,
        triggering_spell_id: Map.get(payload, :spell_id),
        damage: Map.get(payload, :damage, 0),
        proc_damage: Map.get(payload, :proc_damage, Map.get(payload, :damage, 0)),
        attack_time_ms: entity.unit.base_attack_time,
        now: now
      })

    Event.enqueue(entity, events)
  end

  defp trigger_melee_procs(entity, _payload, _spell, _now), do: entity

  defp mark_reactives(entity, %{outcome: :dodge, victim_guid: victim_guid}, now) do
    Reactive.mark_dodging_target(entity, victim_guid, now)
  end

  defp mark_reactives(entity, _payload, _now), do: entity
end
