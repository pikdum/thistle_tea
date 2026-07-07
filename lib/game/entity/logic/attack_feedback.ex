defmodule ThistleTea.Game.Entity.Logic.AttackFeedback do
  @moduledoc """
  Applies the resolved outcome of an entity's own outgoing melee swing,
  delivered back from the defender that rolled the attack table: rage from
  damage dealt and partial rage from dodged or parried swings. Swings that
  carried a queued on-next-swing spell generate no rage.
  """
  alias ThistleTea.Game.Entity.Logic.Resources

  @avoided_rage_factor 0.75

  def receive(entity, %{spell_id: spell_id}, _now) when is_integer(spell_id) do
    entity
  end

  def receive(entity, %{outcome: outcome, damage: damage}, _now)
      when outcome in [:dodge, :parry] and is_number(damage) do
    Resources.gain_attack_rage(entity, damage * @avoided_rage_factor, :dealt)
  end

  def receive(entity, %{outcome: :miss}, _now), do: entity

  def receive(entity, %{damage: damage}, _now) when is_number(damage) and damage > 0 do
    Resources.gain_attack_rage(entity, damage, :dealt)
  end

  def receive(entity, _payload, _now), do: entity
end
