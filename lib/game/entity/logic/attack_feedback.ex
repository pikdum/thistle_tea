defmodule ThistleTea.Game.Entity.Logic.AttackFeedback do
  @moduledoc """
  Applies the resolved outcome of an entity's own outgoing swing or melee
  ability, delivered back from the defender that rolled the attack table: rage
  from damage dealt, partial rage from dodged/parried swings, and the vanilla
  82% power refund when a rage ability is dodged or parried. Swings that
  carried a queued on-next-swing spell generate no rage.
  """
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell

  @avoided_rage_factor 0.75
  @avoided_power_refund 0.82

  def receive(entity, payload, spell \\ nil, now)

  def receive(entity, %{outcome: outcome}, %Spell{} = spell, _now) when outcome in [:dodge, :parry] do
    if Spell.attribute?(spell, :discount_power_on_miss) do
      Resources.refund_power(entity, spell, @avoided_power_refund)
    else
      entity
    end
  end

  def receive(entity, %{spell_id: spell_id}, _spell, _now) when is_integer(spell_id) do
    entity
  end

  def receive(entity, %{outcome: outcome, damage: damage}, _spell, _now)
      when outcome in [:dodge, :parry] and is_number(damage) do
    Resources.gain_attack_rage(entity, damage * @avoided_rage_factor, :dealt)
  end

  def receive(entity, %{outcome: :miss}, _spell, _now), do: entity

  def receive(entity, %{damage: damage}, _spell, _now) when is_number(damage) and damage > 0 do
    Resources.gain_attack_rage(entity, damage, :dealt)
  end

  def receive(entity, _payload, _spell, _now), do: entity
end
