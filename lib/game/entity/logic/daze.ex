defmodule ThistleTea.Game.Entity.Logic.Daze do
  @moduledoc """
  Rolls the vanilla rear-hit daze for uncontrolled creature melee attacks.
  Successful rolls request the ordinary Daze spell, leaving immunity, movement
  changes, refreshes, and expiry to the spell and aura systems.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Math

  @spell_id 1604

  def attacker?(%Mob{unit: %Unit{} = unit, internal: %Internal{pet: nil}}) do
    unit.charmed_by in [nil, 0] and unit.summoned_by in [nil, 0]
  end

  def attacker?(_entity), do: false

  def events(entity, attack, damage, roll) when is_number(damage) and damage > 0 and is_function(roll, 0) do
    if eligible?(entity, attack) and roll.() < chance(entity, attack) do
      [Effects.trigger_spell(attack.caster, attack.caster_level, entity.object.guid, @spell_id)]
    else
      []
    end
  end

  def events(_entity, _attack, _damage, _roll), do: []

  def chance(%{unit: %Unit{level: level}} = entity, %{caster_level: attacker_level} = attack)
      when is_integer(level) and is_integer(attacker_level) do
    base = if level < 30, do: 0.65 * level + 0.5, else: 20.0
    attack_skill = Map.get(attack, :caster_attack_skill) || attacker_level * 5
    (base + (attack_skill - Skills.defense_value(entity)) * 0.2) |> max(0.0) |> min(40.0)
  end

  defp eligible?(entity, %{caster_can_daze?: true, caster: caster, caster_level: level} = attack)
       when is_integer(caster) and is_integer(level) do
    not Map.get(attack, :ranged?, false) and Death.alive?(entity) and
      not protected?(entity) and behind?(entity, Map.get(attack, :caster_position))
  end

  defp eligible?(_entity, _attack), do: false

  defp protected?(%{internal: %Internal{godmode: true}}), do: true

  defp protected?(%{internal: %Internal{invincibility_health_threshold: threshold}})
       when is_number(threshold) and threshold > 0, do: true

  defp protected?(_entity), do: false

  defp behind?(%{movement_block: %{position: {x, y, _z, orientation}}}, {ax, ay, _az}) do
    Math.behind?({x, y, orientation}, {ax, ay})
  end

  defp behind?(_entity, _position), do: false
end
